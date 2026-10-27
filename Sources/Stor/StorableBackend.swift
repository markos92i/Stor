//
//  StorableBackend.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import Foundation
import SwiftUI

/// Backing storage for `@Storable` and `@Keychain`. Bridges to `StorableRegistry` for reactivity.
///
/// Thread-safe and `Sendable`. Can be initialized and accessed from any context.
public struct StorableBackend<T: Sendable>: Sendable {

    private let key: String
    private let defaultValue: T
    private let store: Stor

    public init(key: String, default defaultValue: T, store: Stor = .shared) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    public init(key: String, default defaultValue: T, keychain: KeychainStore) {
        self.init(key: key, default: defaultValue, store: keychain.stor)
    }

    /// Current value.
    ///
    /// - On the main actor: the registry's value, which establishes SwiftUI observation.
    /// - Elsewhere: the store's newest value (a write not persisted yet, else the backend).
    /// - Writing records the value at once and persists it in the background.
    public var value: T {
        get {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    StorableRegistry.shared.get(key, default: defaultValue, store: store)
                }
            }
            if case .found(let value) = store.lookup(key, as: T.self) { return value }
            return defaultValue
        }
        nonmutating set {
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    StorableRegistry.shared.set(key, newValue, store: store)
                }
            } else {
                store.persist(key, newValue)
                let (key, store) = (key, store)
                Task { @MainActor in
                    StorableRegistry.shared.setFromExternal(key, newValue, store: store)
                }
            }
        }
    }

    public typealias Binding = SwiftUI.Binding<T>

    /// What `$property` returns.
    public var binding: Binding {
        Binding(get: { value }, set: { value = $0 })
    }
}
