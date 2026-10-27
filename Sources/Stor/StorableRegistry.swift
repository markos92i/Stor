//
//  StorableRegistry.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import Foundation
import Observation

// MARK: - StorableRegistry

/// Central observable registry that bridges `Stor` persistence with SwiftUI reactivity.
///
/// This singleton keeps an in-memory cache of every `@Storable` and `@Keychain` value, per store
/// location and key. When a value changes (from a property or from the `Stor` programmatic API),
/// every SwiftUI view observing it updates.
@MainActor @Observable
public final class StorableRegistry {

    /// Shared singleton instance.
    public static let shared = StorableRegistry()

    /// A value is identified by where it lives and its key: two stores may use the same key.
    private struct Slot: Hashable {
        let location: String
        let key: String

        init(_ key: String, in store: Stor) {
            self.location = store.location
            self.key = key
        }
    }

    @ObservationIgnored
    private var cache: [Slot: any Sendable] = [:]

    @ObservationIgnored
    private var subscriptions: [Slot: SubscriptionToken] = [:]

    /// Version counters for fine-grained observation: bumping one updates its observers.
    private var versions: [Slot: UInt64] = [:]

    private init() {}

    // MARK: - Public API

    /// The current value, read from the store the first time. Establishes observation.
    public func get<T: Sendable>(_ key: String, default defaultValue: T, store: Stor = .shared) -> T {
        let slot = Slot(key, in: store)
        _ = versions[slot, default: 0]
        if let cached = cached(slot, as: T.self) { return cached }
        return hydrate(key, default: defaultValue, store: store)
    }

    /// Sets a value, persists it in the background and notifies observers.
    public func set<T: Sendable>(_ key: String, _ value: T, store: Stor = .shared) {
        let slot = Slot(key, in: store)
        cache[slot] = value
        versions[slot, default: 0] &+= 1
        store.persist(key, value)
    }

    /// Sets a value written off the main actor. Does not persist (already done).
    public func setFromExternal<T: Sendable>(_ key: String, _ value: T, store: Stor = .shared) {
        let slot = Slot(key, in: store)
        cache[slot] = value
        versions[slot, default: 0] &+= 1
    }

    /// Reads a key from the store if it isn't cached. An unavailable value (a locked keychain)
    /// isn't cached: the next access reads it again.
    public func hydrate<T: Sendable>(_ key: String, default defaultValue: T, store: Stor = .shared) -> T {
        let slot = Slot(key, in: store)
        if let cached = cached(slot, as: T.self) { return cached }

        let value: T
        switch store.lookup(key, as: T.self) {
        case .found(let found): value = found
        case .missing: value = defaultValue
        case .unavailable: return defaultValue
        }
        cache[slot] = value
        ensureSubscription(slot, store: store, type: T.self)
        return value
    }

    // MARK: - Private

    /// `nil` only when the slot isn't cached: casting a missing entry to an optional `T` would give a cached `nil`.
    private func cached<T>(_ slot: Slot, as type: T.Type) -> T? {
        guard let entry = cache[slot] else { return nil }
        return entry as? T
    }

    /// Follows `Stor` changes for this slot (programmatic writes, removals, purges).
    private func ensureSubscription<T: Sendable>(_ slot: Slot, store: Stor, type: T.Type) {
        guard subscriptions[slot] == nil else { return }

        Task { [weak self] in
            let token = await store.subscribe(slot.key) { [weak self] (newValue: T?) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let newValue {
                        self.cache[slot] = newValue
                    } else {
                        self.cache.removeValue(forKey: slot)
                    }
                    self.versions[slot, default: 0] &+= 1
                }
            }
            self?.subscriptions[slot] = token
        }
    }
}
