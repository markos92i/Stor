//
//  MemoryStorage.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation
import Synchronization
@testable import Stor

/// In-memory backend for tests: it can answer `unavailable` (a locked keychain) and delay writes.
actor MemoryStorage: StorageBackend {
    nonisolated let location = "memory:\(UUID().uuidString)"
    private nonisolated let values = Mutex<[String: Data]>([:])
    private nonisolated let state = Mutex(State())

    struct State {
        var available = true
        var writeDelay: Duration = .zero
        var writes = 0
    }

    nonisolated var available: Bool {
        get { state.withLock { $0.available } }
        set { state.withLock { $0.available = newValue } }
    }

    nonisolated var writeDelay: Duration {
        get { state.withLock { $0.writeDelay } }
        set { state.withLock { $0.writeDelay = newValue } }
    }

    nonisolated var writes: Int { state.withLock { $0.writes } }

    /// What the backend holds, bypassing `Stor`.
    nonisolated func stored(_ key: String) -> Data? {
        values.withLock { $0[key] }
    }

    nonisolated func put(_ data: Data, for key: String) {
        values.withLock { $0[key] = data }
    }

    func write(_ data: Data, for key: String) async {
        let delay = writeDelay
        if delay > .zero { try? await Task.sleep(for: delay) }
        values.withLock { $0[key] = data }
        state.withLock { $0.writes += 1 }
    }

    func read(_ key: String) -> Data? {
        if case .found(let data) = readSync(key) { data } else { nil }
    }

    func readAll() -> [String: Data] { values.withLock { $0 } }
    func remove(_ key: String) { values.withLock { _ = $0.removeValue(forKey: key) } }
    func removeAll() { values.withLock { $0.removeAll() } }
    func allKeys() -> [String] { values.withLock { Array($0.keys) } }

    nonisolated func readSync(_ key: String) -> ReadResult {
        guard available else { return .unavailable }
        guard let data = values.withLock({ $0[key] }) else { return .missing }
        return .found(data)
    }
}
