//
//  Storable.swift
//  Dynamic Storable
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import SwiftUI

/// A property wrapper that persists `Codable` values to disk and provides
/// automatic SwiftUI view invalidation.
///
/// Uses `@State` for reliable SwiftUI observation and a shared `StorableStore`
/// cache so that writes from any context (ViewModels, Prefs) are visible
/// to all views on next re-render.
///
/// Usage:
/// ```swift
/// @Storable("user.search.history") var history: [SearchDto] = []
/// ```
@propertyWrapper public struct Storable<T: Sendable>: DynamicProperty, Sendable {
    private let key: String
    private let url: URL?

    @State private var storage: T

    public var wrappedValue: T {
        get {
            // Read from shared cache (source of truth). Falls back to local @State.
            if let cached: T = StorableStore.shared.value(for: key) {
                return cached
            }
            return storage
        }
        nonmutating set {
            storage = newValue

            var hasValue = false
            if T.self is ExpressibleByNilLiteral.Type {
                if "\(newValue)" != "nil" { hasValue = true }
            } else {
                hasValue = true
            }

            if hasValue {
                StorableStore.shared.set(newValue, for: key, url: url)
            } else {
                StorableStore.shared.set(nil as T?, for: key, url: url)
            }
        }
    }

    public var projectedValue: Binding<T> {
        .init(get: { wrappedValue }, set: { wrappedValue = $0 })
    }

    // MARK: - Inits

    private init(wrappedValue: T, key: String) {
        self.key = key
        self.url = Self.storageURL(for: key)

        // Hydrate: cache first, then disk, then default.
        if let value: T = StorableStore.shared.hydrate(key: key, url: Self.storageURL(for: key), as: T.self) {
            _storage = State(initialValue: value)
        } else {
            _storage = State(initialValue: wrappedValue)
        }
    }

    public init(wrappedValue: T, _ key: String) where T: Codable {
        self.init(wrappedValue: wrappedValue, key: key)
    }

    public init(wrappedValue: T, _ key: String) where T == Data {
        self.init(wrappedValue: wrappedValue, key: key)
    }

    #if canImport(UIKit)
    public init(wrappedValue: T, _ key: String) where T == UIImage {
        self.init(wrappedValue: wrappedValue, key: key)
    }

    public init(_ key: String) where T == UIImage? {
        self.key = key
        self.url = Self.storageURL(for: key)
        if let value: T = StorableStore.shared.hydrate(key: key, url: Self.storageURL(for: key), as: T.self) {
            _storage = State(initialValue: value)
        } else {
            _storage = State(initialValue: nil)
        }
    }
    #endif

    // MARK: - Storage URL

    private static func storageURL(for key: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(key)
    }
}

// MARK: - Optional support

extension Storable where T: ExpressibleByNilLiteral {
    private init(key: String) {
        self.key = key
        self.url = Self.storageURL(for: key)
        if let value: T = StorableStore.shared.hydrate(key: key, url: Self.storageURL(for: key), as: T.self) {
            _storage = State(initialValue: value)
        } else {
            _storage = State(initialValue: nil)
        }
    }

    public init(_ key: String) where T: Codable {
        self.init(key: key)
    }

    public init(_ key: String) where T == Data? {
        self.init(key: key)
    }
}

// MARK: - Raw Storage Protocol

protocol RawStorable {
    func toData() -> Data
    static func fromData(_ data: Data) -> Self?
}

extension Data: RawStorable {
    func toData() -> Data { self }
    static func fromData(_ data: Data) -> Data? { data }
}

#if canImport(UIKit)
extension UIImage: RawStorable {
    func toData() -> Data { pngData() ?? Data() }
    static func fromData(_ data: Data) -> Self? { Self(data: data) }
}
#endif

// MARK: - Optional support for RawStorable

protocol AnyOptionalStorable {
    static var wrappedStorableType: RawStorable.Type? { get }
}

extension Optional: AnyOptionalStorable {
    static var wrappedStorableType: RawStorable.Type? { Wrapped.self as? RawStorable.Type }
}

// MARK: - Optional support for Codable

/// Enables direct encode/decode of the wrapped Codable type inside an Optional.
protocol AnyCodableOptional {
    func encodeWrappedValue() -> Data?
    static func decodeWrappedValue(from data: Data) -> Any?
}

extension Optional: AnyCodableOptional {
    func encodeWrappedValue() -> Data? {
        guard let value = self, let codable = value as? any Codable else { return nil }
        return try? JSONEncoder().encode(codable)
    }

    static func decodeWrappedValue(from data: Data) -> Any? {
        guard let codableType = Wrapped.self as? any Codable.Type else { return nil }
        guard let decoded = try? JSONDecoder().decode(codableType, from: data) else { return nil }
        return Self.some(decoded as! Wrapped)
    }
}
