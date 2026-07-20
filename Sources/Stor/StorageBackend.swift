//
//  StorageBackend.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 19/07/2026.
//

import Foundation

// MARK: - StorageBackend

/// Protocol for pluggable storage backends. Must be an actor.
/// `readSync(_:)` is nonisolated for synchronous hydration at init.
public protocol StorageBackend: Actor, Sendable {
    func write(_ data: Data, for key: String) async
    func read(_ key: String) async -> Data?
    func readAll() async -> [String: Data]
    func remove(_ key: String) async
    func removeAll() async
    func purge() async
    func allKeys() async -> [String]
    nonisolated func readSync(_ key: String) -> Data?
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
