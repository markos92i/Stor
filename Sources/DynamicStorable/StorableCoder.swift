//
//  StorableCoder.swift
//  DynamicStorable
//
//  Created by Marcos del Castillo Camacho on 26/06/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Centralized encoding/decoding logic for `Storable` values.
enum StorableCoder {
    static func encode<T>(_ value: T) throws -> Data {
        if let raw = value as? RawStorable { return raw.toData() }
        if let optionalCodable = value as? AnyCodableOptional, let data = optionalCodable.encodeWrappedValue() { return data }
        guard let codable = value as? Codable else { throw StorableError.conversionError }
        return try JSONEncoder().encode(codable)
    }

    static func decode<T>(_ data: Data) throws(StorableError) -> T {
        if let type = T.self as? RawStorable.Type {
            guard let value = type.fromData(data) as? T else { throw .conversionError }
            return value
        }
        if let optionalType = T.self as? AnyOptionalStorable.Type, let rawType = optionalType.wrappedStorableType {
            guard let value = rawType.fromData(data) as? T else { throw .conversionError }
            return value
        }
        guard let type = T.self as? Codable.Type else { throw .conversionError }
        do {
            return try JSONDecoder().decode(type, from: data) as! T
        } catch {
            throw .conversionError
        }
    }
}
