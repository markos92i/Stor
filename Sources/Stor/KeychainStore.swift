//
//  KeychainStore.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 27/10/2026.
//

import Foundation

// MARK: - KeychainStore

/// A store whose values live in the keychain. The only store `@Keychain` accepts.
public struct KeychainStore: Sendable {
    /// The app's keychain: service = bundle identifier, readable when unlocked.
    public static let shared = KeychainStore()

    public let stor: Stor

    public init(accessibility: KeychainAccessibility = .whenUnlocked, accessGroup: String? = nil) {
        // Default JSON strategies and Codable before RawStorable: DynamicKeychain's format.
        stor = Stor(
            backend: KeychainStorage(accessibility: accessibility, accessGroup: accessGroup),
            encoder: JSONEncoder(),
            decoder: JSONDecoder(),
            codableFirst: true
        )
    }

    // MARK: - Programmatic access

    /// Returns the decoded value for `key`, or `nil` if absent.
    public func get<T: Sendable>(_ key: String) async -> T? {
        await stor.get(key)
    }

    /// Stores `value` for `key`. Passing `nil` removes the key. `@Keychain` properties refresh.
    public func set<T: Sendable>(_ key: String, _ value: T?) async {
        await stor.set(key, value)
    }

    /// Removes the value for `key`.
    public func remove(_ key: String) async {
        await stor.remove(key)
    }

    /// Removes the values for `keys`, also items no `@Keychain` declares any more.
    public func remove(keys: [String]) async {
        for key in keys { await stor.remove(key) }
    }

    /// Deletes every item of this store's service (and access group). Use on logout.
    public func purge() async {
        await stor.purge()
    }
}
