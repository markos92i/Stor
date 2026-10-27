//
//  StorageBackend.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 19/07/2026.
//

import Foundation

// MARK: - ReadResult

/// A synchronous read: `unavailable` (e.g. a locked keychain) is retried on the next access.
public enum ReadResult: Sendable {
    case found(Data)
    case missing
    case unavailable
}

// MARK: - StorageBackend

/// Protocol for pluggable storage backends. Must be an actor.
/// `readSync(_:)` is nonisolated for synchronous reads from any thread.
public protocol StorageBackend: Actor, Sendable {
    /// Where the data lives (a directory, a keychain service). Two stores at the same location share values.
    nonisolated var location: String { get }
    func write(_ data: Data, for key: String) async
    func read(_ key: String) async -> Data?
    func readAll() async -> [String: Data]
    func remove(_ key: String) async
    func removeAll() async
    func purge() async
    func allKeys() async -> [String]
    nonisolated func readSync(_ key: String) -> ReadResult
}

// MARK: - Default implementations

extension StorageBackend {
    public func write(_ pairs: [(key: String, data: Data)]) async {
        for pair in pairs { await write(pair.data, for: pair.key) }
    }

    public func remove(keys: [String]) async {
        for key in keys { await remove(key) }
    }

    public func purge() async {
        await removeAll()
    }
}
