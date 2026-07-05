//
//  StorableError.swift
//  Dynamic Storable
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

import Foundation

public enum StorableError: Error, Sendable {
    case saveError
    case readError
    case conversionError
    case unexpectedData
}
