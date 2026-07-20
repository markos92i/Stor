//
//  StorableError.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 29/3/25.
//

import Foundation

public enum StorableError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}
