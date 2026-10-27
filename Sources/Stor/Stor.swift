//
//  Stor.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 18/07/2026.
//

import Foundation
import Logy
import Synchronization

// MARK: - Stor

/// Actor-isolated persistent key-value store. Programmatic interface for reading,
/// writing, and observing persisted values from any context.
public actor Stor {
    public static let shared = Stor()

    // MARK: - Properties

    public let backend: any StorageBackend
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    /// Encodes a type that is both Codable and RawStorable (like `Data`) as JSON: the keychain format.
    nonisolated let codableFirst: Bool
    nonisolated let kind: StoreKind
    private nonisolated let log = Logy<StorLog>()

    private var subscriptions: [String: [UUID: @Sendable (Data?) -> Void]] = [:]

    /// Writes not in the backend yet, so a read from any thread sees the newest one.
    private nonisolated let pending = Mutex(Pending())
    /// The write queued for each key: each one waits for the previous, so writes land in order.
    private var writers: [String: Task<Void, Never>] = [:]

    struct Pending {
        var writes: [String: PendingWrite] = [:]
        var version: UInt64 = 0
    }

    /// `value == nil` removes the key.
    struct PendingWrite {
        let value: (any Sendable)?
        let version: UInt64
    }

    // MARK: - Init

    public init(
        directory: URL? = nil,
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil
    ) {
        let enc = encoder ?? Self.defaultEncoder
        let dec = decoder ?? Self.defaultDecoder
        let dir = directory ?? Self.defaultDirectory
        self.init(backend: DiskStorage(directory: dir, encoder: enc, decoder: dec), encoder: enc, decoder: dec)
    }

    public init(
        backend: any StorageBackend,
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil
    ) {
        self.init(backend: backend, encoder: encoder, decoder: decoder, codableFirst: false)
    }

    init(backend: any StorageBackend, encoder: JSONEncoder?, decoder: JSONDecoder?, codableFirst: Bool) {
        self.backend = backend
        self.encoder = encoder ?? Self.defaultEncoder
        self.decoder = decoder ?? Self.defaultDecoder
        self.codableFirst = codableFirst
        self.kind = StoreKind(backend)
    }

    /// Where the values live; stores at the same location share `@Storable` values.
    public nonisolated var location: String { backend.location }

    // MARK: - Read

    /// Returns the decoded value for `key`, or `nil` if absent.
    public func get<T: Sendable>(_ key: String) async -> T? {
        if let write = pending.withLock({ $0.writes[key] }) { return write.value as? T }
        guard let data = await backend.read(key) else { return nil }
        return decode(data, for: key)
    }

    // MARK: - Write

    /// Stores `value` for `key`. Passing `nil` removes the key.
    public func set<T: Sendable>(_ key: String, _ value: T?) async {
        stage(key, value.flatMap { StorableCoder.isNil($0) ? nil : $0 })
        await flush(key)
    }

    /// Non-optional overload.
    public func set<T: Sendable>(_ key: String, _ value: T) async {
        stage(key, StorableCoder.isNil(value) ? nil : value)
        await flush(key)
    }

    /// Removes the value for `key`.
    public func remove(_ key: String) async {
        stage(key, nil)
        await flush(key)
    }

    /// Removes all values.
    public func removeAll() async {
        let keys = await settleAndList()
        await backend.removeAll()
        log.log(.purge(store: kind, keys: keys.count))
        keys.forEach { notifySubscribers(for: $0, data: nil) }
    }

    /// Destroys all persisted data. Use on logout or app reset.
    public func purge() async {
        let keys = await settleAndList()
        await backend.purge()
        log.log(.purge(store: kind, keys: keys.count))
        keys.forEach { notifySubscribers(for: $0, data: nil) }
    }

    // MARK: - Property writes

    /// Records `value` now and writes it to the backend in the background; `nil` removes the key.
    nonisolated func persist<T: Sendable>(_ key: String, _ value: T) {
        stage(key, StorableCoder.isNil(value) ? nil : value)
        Task { await flush(key) }
    }

    /// The newest value of `key` from any thread: the pending write, else the backend.
    nonisolated func lookup<T: Sendable>(_ key: String, as type: T.Type) -> Lookup<T> {
        if let write = pending.withLock({ $0.writes[key] }) {
            guard let value = write.value else { return .missing }
            if let value = value as? T { return .found(value) }
        }
        switch backend.readSync(key) {
        case .found(let data):
            log.log(.read(key: key, store: kind, bytes: data.count))
            guard let value: T = decode(data, for: key) else { return .missing }
            return .found(value)
        case .missing:
            log.log(.read(key: key, store: kind, bytes: nil))
            return .missing
        case .unavailable:
            return .unavailable
        }
    }

    enum Lookup<T> {
        case found(T)
        case missing
        case unavailable
    }

    // MARK: - Subscriptions

    /// Subscribes to changes for `key`. Returns a token — release it to stop.
    public func subscribe<T: Sendable>(
        _ key: String,
        handler: @escaping @Sendable (T?) -> Void
    ) -> SubscriptionToken {
        let id = UUID()
        let dec = decoder
        let codableFirst = codableFirst

        subscriptions[key, default: [:]][id] = { data in
            guard let data else { handler(nil); return }
            handler(StorableCoder.decode(data, as: T.self, using: dec, codableFirst: codableFirst))
        }

        return SubscriptionToken {
            Task { await self.unsubscribe(key: key, id: id) }
        }
    }

    // MARK: - Pending writes

    private nonisolated func stage(_ key: String, _ value: (any Sendable)?) {
        pending.withLock { state in
            state.version &+= 1
            state.writes[key] = PendingWrite(value: value, version: state.version)
        }
    }

    /// Queues a write of the newest pending value of `key` behind the ones already queued for it.
    private func flush(_ key: String) async {
        let previous = writers[key]
        let writer = Task {
            await previous?.value
            await writeNewest(key)
        }
        writers[key] = writer
        await writer.value
        if writers[key] == writer { writers[key] = nil }
    }

    /// Nothing to do when an earlier writer already wrote the newest value.
    private func writeNewest(_ key: String) async {
        guard let write = pending.withLock({ $0.writes[key] }) else { return }
        if let value = write.value {
            guard let data = StorableCoder.encode(value, with: encoder, codableFirst: codableFirst) else {
                log.log(.failed(key: key, store: kind, step: "encode", detail: "\(type(of: value)) is neither Codable, RawStorable nor RawRepresentable"))
                clear(write, for: key)
                return
            }
            let interval = log.begin("write", key, on: kind.channel)
            await backend.write(data, for: key)
            log.log(.write(key: key, store: kind, bytes: data.count, elapsed: log.end(interval)))
            clear(write, for: key)
            notifySubscribers(for: key, data: data)
        } else {
            await backend.remove(key)
            log.log(.remove(key: key, store: kind))
            clear(write, for: key)
            notifySubscribers(for: key, data: nil)
        }
    }

    /// A newer write staged meanwhile stays pending for the writer queued behind.
    private func clear(_ write: PendingWrite, for key: String) {
        pending.withLock { state in
            if state.writes[key]?.version == write.version { state.writes[key] = nil }
        }
    }

    /// Drops pending writes and waits for the ones in progress, so none lands after a purge.
    private func settleAndList() async -> [String] {
        pending.withLock { $0.writes.removeAll() }
        for writer in writers.values { await writer.value }
        return await backend.allKeys()
    }

    // MARK: - Private

    private nonisolated func decode<T>(_ data: Data, for key: String) -> T? {
        guard let value = StorableCoder.decode(data, as: T.self, using: decoder, codableFirst: codableFirst) else {
            log.log(.failed(key: key, store: kind, step: "decode", detail: "stored data is not a \(T.self)"))
            return nil
        }
        return value
    }

    private func unsubscribe(key: String, id: UUID) {
        subscriptions[key]?.removeValue(forKey: id)
        if subscriptions[key]?.isEmpty == true {
            subscriptions.removeValue(forKey: key)
        }
    }

    private func notifySubscribers(for key: String, data: Data?) {
        guard let handlers = subscriptions[key] else { return }
        for handler in handlers.values {
            Task { @MainActor in handler(data) }
        }
    }

    private static let defaultEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let defaultDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(component: "stor", directoryHint: .isDirectory)
    }

    // MARK: - Internal (testing)

    func rawJSON(for key: String) async -> String? {
        guard let data = await backend.read(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setRaw(_ key: String, _ data: Data) async {
        await backend.write(data, for: key)
        notifySubscribers(for: key, data: data)
    }
}
