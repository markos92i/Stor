//
//  StorableRegistry.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import Foundation
import Observation
import Synchronization

// MARK: - StorableRegistry

/// Central observable registry that bridges `Stor` persistence with SwiftUI reactivity.
///
/// This singleton maintains an in-memory cache of all `@Storable` values and provides
/// `@Observable` reactivity. When values change (either locally or from `Stor` programmatic
/// API), all SwiftUI views observing that key automatically update.
///
/// Thread-safe: reads/writes use `Mutex`. SwiftUI notifications dispatch to MainActor.
@MainActor @Observable
public final class StorableRegistry {
    
    /// Shared singleton instance.
    public static let shared = StorableRegistry()
    
    /// In-memory cache of values by key. Access via subscript.
    @ObservationIgnored
    private var cache: [String: any Sendable] = [:]
    
    /// Tracks which keys have active subscriptions to Stor.
    @ObservationIgnored
    private var subscriptions: [String: SubscriptionToken] = [:]
    
    /// Version counters for fine-grained observation.
    /// Incrementing a key's version triggers SwiftUI updates for observers of that key.
    private var versions: [String: UInt64] = [:]
    
    private init() {}
    
    // MARK: - Public API
    
    /// Gets the current value for a key, or returns the default if not cached.
    ///
    /// This method establishes an observation dependency — SwiftUI views calling this
    /// will re-render when the value changes.
    public func get<T: Sendable>(_ key: String, default defaultValue: T) -> T {
        // Touch version to establish observation
        _ = versions[key, default: 0]
        return (cache[key] as? T) ?? defaultValue
    }
    
    /// Sets a value for a key. Persists to `Stor` and notifies observers.
    ///
    /// Safe to call from MainActor (SwiftUI). Persistence happens async.
    public func set<T: Sendable>(_ key: String, _ value: T, store: Stor = .shared) {
        cache[key] = value
        versions[key, default: 0] &+= 1
        
        // Persist asynchronously
        Task {
            await store.set(key, value)
        }
    }
    
    /// Sets a value from an external source (background write). Does not persist (already done).
    public func setFromExternal<T: Sendable>(_ key: String, _ value: T) {
        cache[key] = value
        versions[key, default: 0] &+= 1
    }
    
    /// Hydrates a key from disk if not already cached. Call during init.
    ///
    /// - Returns: The hydrated value or the default.
    public func hydrate<T: Sendable>(_ key: String, default defaultValue: T, store: Stor = .shared) -> T {
        // Already cached?
        if let cached = cache[key] as? T {
            return cached
        }
        
        // Hydrate from disk synchronously
        if let data = store.backend.readSync(key),
           let decoded: T = StorableCoder.decode(data, as: T.self, using: store.decoder) {
            cache[key] = decoded
            ensureSubscription(key: key, store: store, type: T.self)
            return decoded
        }
        
        // Use default
        cache[key] = defaultValue
        ensureSubscription(key: key, store: store, type: T.self)
        return defaultValue
    }
    
    // MARK: - Private
    
    /// Ensures we're subscribed to Stor changes for this key.
    private func ensureSubscription<T: Sendable>(key: String, store: Stor, type: T.Type) {
        guard subscriptions[key] == nil else { return }
        
        Task { [weak self] in
            guard let self else { return }
            let token = await store.subscribe(key) { [weak self] (newValue: T?) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let newValue {
                        self.cache[key] = newValue
                    } else {
                        self.cache.removeValue(forKey: key)
                    }
                    self.versions[key, default: 0] &+= 1
                }
            }
            await MainActor.run { [weak self] in
                self?.subscriptions[key] = token
            }
        }
    }
}
