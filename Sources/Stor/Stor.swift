//
//  Stor.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 18/07/2026.
//

import Foundation

// MARK: - Stor

/// Actor-isolated persistent key-value store. Programmatic interface for reading,
/// writing, and observing persisted values from any context.
public actor Stor {
    public static let shared = Stor()

    // MARK: - Properties

    public let backend: any StorageBackend
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    private var subscriptions: [String: [UUID: @Sendable (Data?) -> Void]] = [:]

    // MARK: - Init

    public init(
        directory: URL? = nil,
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil
    ) {
        let enc = encoder ?? Self.defaultEncoder
        let dec = decoder ?? Self.defaultDecoder
        let dir = directory ?? Self.defaultDirectory
        self.backend = DiskStorage(directory: dir, encoder: enc, decoder: dec)
        self.encoder = enc
        self.decoder = dec
    }

    public init(
        backend: any StorageBackend,
        encoder: JSONEncoder? = nil,
        decoder: JSONDecoder? = nil
    ) {
        self.backend = backend
        self.encoder = encoder ?? Self.defaultEncoder
        self.decoder = decoder ?? Self.defaultDecoder
    }

    // MARK: - Read

    /// Returns the decoded value for `key`, or `nil` if absent.
    public func get<T: Sendable>(_ key: String) async -> T? {
        guard let data = await backend.read(key) else { return nil }
        return StorableCoder.decode(data, as: T.self, using: decoder)
    }

    // MARK: - Write

    /// Stores `value` for `key`. Passing `nil` removes the key.
    public func set<T: Sendable>(_ key: String, _ value: T?) async {
        if let value, let data = StorableCoder.encode(value, with: encoder) {
            await backend.write(data, for: key)
            notifySubscribers(for: key, data: data)
        } else {
            await backend.remove(key)
            notifySubscribers(for: key, data: nil)
        }
    }

    /// Non-optional overload.
    public func set<T: Sendable>(_ key: String, _ value: T) async {
        guard let data = StorableCoder.encode(value, with: encoder) else { return }
        await backend.write(data, for: key)
        notifySubscribers(for: key, data: data)
    }

    /// Removes the value for `key`.
    public func remove(_ key: String) async {
        await backend.remove(key)
        notifySubscribers(for: key, data: nil)
    }

    /// Removes all values.
    public func removeAll() async {
        let keys = await backend.allKeys()
        await backend.removeAll()
        keys.forEach { notifySubscribers(for: $0, data: nil) }
    }

    /// Destroys all persisted data. Use on logout or app reset.
    public func purge() async {
        let keys = await backend.allKeys()
        await backend.purge()
        keys.forEach { notifySubscribers(for: $0, data: nil) }
    }

    // MARK: - Subscriptions

    /// Subscribes to changes for `key`. Returns a token — release it to stop.
    public func subscribe<T: Sendable>(
        _ key: String,
        handler: @escaping @Sendable (T?) -> Void
    ) -> SubscriptionToken {
        let id = UUID()
        let dec = decoder

        subscriptions[key, default: [:]][id] = { data in
            guard let data else { handler(nil); return }
            handler(StorableCoder.decode(data, as: T.self, using: dec))
        }

        return SubscriptionToken {
            Task { await self.unsubscribe(key: key, id: id) }
        }
    }

    // MARK: - Private

    private func unsubscribe(key: String, id: UUID) {
        subscriptions[key]?.removeValue(forKey: id)
        if subscriptions[key]?.isEmpty == true {
            subscriptions.removeValue(forKey: key)
        }
    }

    private func notifySubscribers(for key: String, data: Data?) {
        guard let handlers = subscriptions[key] else { return }
        for handler in handlers.values { handler(data) }
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
