//
//  RawStorable.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 19/07/2026.
//

import Foundation

// MARK: - RawStorable

/// Types that serialize to/from raw `Data` without `Codable`.
/// Conform for binary types like images, protobuf, etc.
public protocol RawStorable: Sendable {
    func toData() -> Data?
    static func fromData(_ data: Data) -> Self?
}

extension Data: RawStorable {
    public func toData() -> Data? { self }
    public static func fromData(_ data: Data) -> Data? { data }
}

// MARK: - Optional RawStorable support

protocol AnyOptionalRawStorable {
    static var wrappedRawStorableType: RawStorable.Type? { get }
}

extension Optional: AnyOptionalRawStorable {
    static var wrappedRawStorableType: RawStorable.Type? {
        Wrapped.self as? RawStorable.Type
    }
}

// MARK: - Optional Codable support

protocol AnyOptionalCodable {
    func encodeWrappedValue(with encoder: JSONEncoder) -> Data?
    static func decodeWrappedValue(from data: Data, using decoder: JSONDecoder) -> Any?
}

extension Optional: AnyOptionalCodable {
    func encodeWrappedValue(with encoder: JSONEncoder) -> Data? {
        guard let value = self, let codable = value as? any Codable else { return nil }
        return try? encoder.encode(codable)
    }

    static func decodeWrappedValue(from data: Data, using decoder: JSONDecoder) -> Any? {
        guard let codableType = Wrapped.self as? any Codable.Type else { return nil }
        guard let decoded = try? decoder.decode(codableType, from: data) else { return nil }
        return Self.some(decoded as! Wrapped)
    }
}

// MARK: - StorableCoder

/// Runtime encoder/decoder. Resolves Codable vs RawStorable automatically.
enum StorableCoder {

    static func encode<T>(_ value: T, with encoder: JSONEncoder) -> Data? {
        if let raw = value as? RawStorable { return raw.toData() }
        if let optCodable = value as? AnyOptionalCodable,
           let data = optCodable.encodeWrappedValue(with: encoder) { return data }
        guard let codable = value as? any Codable else { return nil }
        return try? encoder.encode(codable)
    }

    static func decode<T>(_ data: Data, as type: T.Type, using decoder: JSONDecoder) -> T? {
        if let rawType = T.self as? RawStorable.Type {
            return rawType.fromData(data) as? T
        }
        if let optType = T.self as? AnyOptionalRawStorable.Type,
           let rawType = optType.wrappedRawStorableType {
            return rawType.fromData(data) as? T
        }
        if let optType = T.self as? AnyOptionalCodable.Type {
            return optType.decodeWrappedValue(from: data, using: decoder) as? T
        }
        guard let codableType = T.self as? any Codable.Type else { return nil }
        guard let decoded = try? decoder.decode(codableType, from: data) else { return nil }
        return decoded as? T
    }
}

// MARK: - UIImage + RawStorable

#if canImport(UIKit)
import UIKit

extension UIImage: RawStorable {
    public func toData() -> Data? { pngData() }
    public static func fromData(_ data: Data) -> Self? { Self(data: data) }
}
#endif
