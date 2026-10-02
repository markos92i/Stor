//
//  StorableBackend.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import Foundation
import Synchronization

/// Backing storage for `@Storable` macro. Bridges to `StorableRegistry` for reactivity.
///
/// Thread-safe and `Sendable`. Can be initialized and accessed from any context.
/// Writes from background threads are dispatched to MainActor automatically.
public struct StorableBackend<T: Sendable>: Sendable {
    
    private let key: String
    private let defaultValue: T
    private let store: Stor
    
    /// Hydrated initial value, cached for synchronous access.
    private let initialValue: T
    
    /// Creates a backend and hydrates the initial value from disk synchronously.
    public init(key: String, default defaultValue: T, store: Stor = .shared) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
        
        // Hydrate from disk synchronously (nonisolated context)
        if let data = store.backend.readSync(key),
           let decoded: T = StorableCoder.decode(data, as: T.self, using: store.decoder) {
            self.initialValue = decoded
        } else {
            self.initialValue = defaultValue
        }
        
        // Schedule registry hydration on MainActor (for subscription setup)
        let k = key
        let d = defaultValue
        let s = store
        Task { @MainActor in
            _ = StorableRegistry.shared.hydrate(k, default: d, store: s)
        }
    }
    
    /// Current value.
    ///
    /// - Reading: Returns cached value. If on MainActor, establishes SwiftUI observation.
    /// - Writing: Persists to `Stor`. If on MainActor, updates registry immediately.
    ///   If on background, dispatches to MainActor for UI update.
    public var value: T {
        get {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    StorableRegistry.shared.get(key, default: initialValue)
                }
            } else {
                // Background read: return cached initial value
                // (registry may have newer value but we can't access it safely)
                return initialValue
            }
        }
        nonmutating set {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    StorableRegistry.shared.set(key, newValue, store: store)
                }
            } else {
                // Background write: dispatch to MainActor for UI update
                // Also persist directly for immediate disk write
                Task { await store.set(key, newValue) }
                Task { @MainActor in
                    StorableRegistry.shared.setFromExternal(key, newValue)
                }
            }
        }
    }
}
