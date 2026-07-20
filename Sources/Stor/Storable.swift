//
//  Storable.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import SwiftUI
import Observation
import Synchronization

// MARK: - @Storable

/// Reactive property wrapper backed by `Stor`. Works like `@AppStorage` for any type.
@propertyWrapper
public struct Storable<T: Sendable>: DynamicProperty, Sendable {

    @State private var observer: StorableObserver<T>

    public init(wrappedValue: T, _ key: String, store: Stor = .shared) {
        _observer = State(initialValue: StorableObserver(
            key: key, store: store, defaultValue: wrappedValue
        ))
    }

    public var wrappedValue: T {
        get { observer.value }
        nonmutating set { observer.write(newValue) }
    }

    public var projectedValue: Binding<T> {
        Binding(get: { observer.value }, set: { observer.write($0) })
    }
}

// MARK: - Optional init

extension Storable where T: ExpressibleByNilLiteral {
    public init(_ key: String, store: Stor = .shared) {
        _observer = State(initialValue: StorableObserver(
            key: key, store: store, defaultValue: nil
        ))
    }
}

// MARK: - StorableObserver

/// `@Observable` backing store for `@Storable`. Hydrates from disk at init,
/// subscribes to `Stor` for cross-context reactivity.
@Observable
final class StorableObserver<T: Sendable>: @unchecked Sendable {

    @ObservationIgnored private let _state: Mutex<T>
    @ObservationIgnored private let key: String
    @ObservationIgnored private let store: Stor
    @ObservationIgnored private let defaultValue: T
    @ObservationIgnored private var token: SubscriptionToken?

    var value: T {
        get {
            access(keyPath: \.value)
            return _state.withLock { $0 }
        }
        set {
            withMutation(keyPath: \.value) {
                _state.withLock { $0 = newValue }
            }
        }
    }

    nonisolated init(key: String, store: Stor, defaultValue: T) {
        self.key = key
        self.store = store
        self.defaultValue = defaultValue

        if let data = store.backend.readSync(key),
           let decoded: T = StorableCoder.decode(data, as: T.self, using: store.decoder) {
            self._state = Mutex(decoded)
        } else {
            self._state = Mutex(defaultValue)
        }

        Task { [weak self] in
            guard let self else { return }
            self.token = await store.subscribe(key) { [weak self] (newValue: T?) in
                self?.update(newValue)
            }
            if let data = await store.backend.read(key),
               let fresh: T = StorableCoder.decode(data, as: T.self, using: store.decoder) {
                self.update(fresh)
            }
        }
    }

    private func update(_ newValue: T?) {
        value = newValue ?? defaultValue
    }

    nonisolated func write(_ newValue: T) {
        withMutation(keyPath: \.value) {
            _state.withLock { $0 = newValue }
        }
        Task { await store.set(key, newValue) }
    }
}
