//
//  StorableStore.swift
//  DynamicStorable
//
//  Created by Marcos del Castillo Camacho on 26/06/2026.
//

import Foundation

/// Shared in-memory cache that backs all `Storable` instances.
///
/// Provides cross-view synchronization: when any `Storable` writes a value,
/// all other `Storable` instances for the same key pick up the change
/// on their next SwiftUI `update()` cycle via the version counter.
///
/// Thread safety: access is guaranteed to be on the main thread because
/// `Storable` is a `DynamicProperty` (views) and ViewModels are `@MainActor`.
public final class StorableStore: @unchecked Sendable {
    public static let shared = StorableStore()

    private var cache: [String: Any] = [:]
    private(set) var version: Int = 0

    private init() {}

    // MARK: - Read

    func value<T: Sendable>(for key: String) -> T? {
        cache[key] as? T
    }

    // MARK: - Write

    func set<T: Sendable>(_ value: T?, for key: String, url: URL?) {
        if let value {
            cache[key] = value
            persist(value, to: url)
        } else {
            cache.removeValue(forKey: key)
            remove(url: url)
        }
        version += 1
    }

    // MARK: - Hydrate

    /// Loads from disk into cache if not already present. Returns the value.
    func hydrate<T: Sendable>(key: String, url: URL?, as type: T.Type) -> T? {
        if let existing = cache[key] as? T { return existing }

        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded: T = try? StorableCoder.decode(data) else { return nil }

        cache[key] = decoded
        return decoded
    }

    // MARK: - Persistence

    private func persist<T>(_ value: T, to url: URL?) {
        guard let url, let data = try? StorableCoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func remove(url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path()) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
