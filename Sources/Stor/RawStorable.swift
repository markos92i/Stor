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

// MARK: - Optional support

protocol OptionalValue {
    var isNil: Bool { get }
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalValue {
    var isNil: Bool { self == nil }
    static var wrappedType: Any.Type { Wrapped.self }
}

// MARK: - StorableCoder

/// Runtime encoder/decoder: `Codable` as JSON, `RawStorable` as its data, and
/// `RawRepresentable` enums that aren't Codable as their raw value (`Int` bytes, `String` UTF-8).
enum StorableCoder {

    /// `true` for an empty `Optional`, also one held in a non-optional generic `T`.
    static func isNil<T>(_ value: T) -> Bool {
        (value as Any as? any OptionalValue)?.isNil ?? false
    }

    /// `codableFirst` encodes a type that is both (like `Data`) as JSON, as the keychain format does.
    static func encode<T>(_ value: T, with encoder: JSONEncoder, codableFirst: Bool = false) -> Data? {
        if isNil(value) { return nil }
        let value: Any = value
        if !codableFirst, let raw = value as? RawStorable { return raw.toData() }
        if let codable = value as? any Encodable { return try? encoder.encode(codable) }
        if let raw = value as? RawStorable { return raw.toData() }
        if let representable = value as? any RawRepresentable {
            switch representable.rawValue {
            case let int as Int: return withUnsafeBytes(of: int) { Data($0) }
            case let string as String: return Data(string.utf8)
            default: return nil
            }
        }
        return nil
    }

    static func decode<T>(_ data: Data, as type: T.Type, using decoder: JSONDecoder, codableFirst: Bool = false) -> T? {
        let target = (T.self as? any OptionalValue.Type)?.wrappedType ?? T.self
        return decodeValue(data, as: target, using: decoder, codableFirst: codableFirst) as? T
    }

    private static func decodeValue(_ data: Data, as type: Any.Type, using decoder: JSONDecoder, codableFirst: Bool) -> Any? {
        if !codableFirst, let raw = type as? RawStorable.Type { return raw.fromData(data) }
        if let codable = type as? any Decodable.Type { return try? decoder.decode(codable, from: data) }
        if let raw = type as? RawStorable.Type { return raw.fromData(data) }
        if let representable = type as? any RawRepresentable<Int>.Type {
            var value = 0
            guard data.count == MemoryLayout<Int>.size else { return nil }
            _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
            return representable.init(rawValue: value)
        }
        if let representable = type as? any RawRepresentable<String>.Type {
            return String(data: data, encoding: .utf8).flatMap { representable.init(rawValue: $0) }
        }
        return nil
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
