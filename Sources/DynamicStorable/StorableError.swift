//
//  StorableError.swift
//  Randstad Empleo
//
//  Created by Marcos del Castillo Camacho on 29/3/25.
//  Copyright © 2025 SNGULAR. All rights reserved.
//

import Foundation

public enum StorableError: Error, Sendable {
    case saveError
    case readError
    case conversionError
    case unexpectedData
}
