//
//  Storable.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 23/03/2026.
//

// MARK: - @Storable Macro Declaration

/// Persists a property in a file (`Stor`), with SwiftUI reactivity and a `$property` binding.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro Storable(_ key: String, store: Stor = .shared) = #externalMacro(module: "StorMacros", type: "StorableMacro")

// MARK: - @Keychain Macro Declaration

/// Persists a property in the keychain (`KeychainStore`), with SwiftUI reactivity and a `$property` binding.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro Keychain(_ key: String, store: KeychainStore = .shared) = #externalMacro(module: "StorMacros", type: "KeychainMacro")
