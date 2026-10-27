//
//  StorableMacro.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// `@Storable("key")` backs a stored property with `Stor` (a file) and adds a `$property` binding.
///
/// ```swift
/// @Storable("theme") var theme: Theme = .system
/// // expands to
/// var theme: Theme {
///     get { _theme_stor.value }
///     nonmutating set { _theme_stor.value = newValue }
/// }
/// private let _theme_stor = StorableBackend<Theme>(key: "theme", default: .system, store: .shared)
/// var $theme: StorableBackend<Theme>.Binding { _theme_stor.binding }
/// ```
public struct StorableMacro: AccessorMacro, PeerMacro {
    static let backing = BackingMacro(name: "Storable", storeLabel: "store")

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        try backing.accessors(of: declaration)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try backing.peers(of: node, declaration)
    }
}

/// `@Keychain("key")`: the same expansion as `@Storable`, backed by a `KeychainStore`.
public struct KeychainMacro: AccessorMacro, PeerMacro {
    static let backing = BackingMacro(name: "Keychain", storeLabel: "keychain")

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        try backing.accessors(of: declaration)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try backing.peers(of: node, declaration)
    }
}

// MARK: - Shared expansion

struct BackingMacro {
    /// The attribute name, for diagnostics.
    let name: String
    /// The `StorableBackend` init label the `store:` argument goes to.
    let storeLabel: String

    func accessors(of declaration: some DeclSyntaxProtocol) throws -> [AccessorDeclSyntax] {
        let identifier = try identifier(of: declaration)
        let backingName = "_\(identifier)_stor"

        // `nonmutating set` allows using it in `static let` singletons.
        let getter: AccessorDeclSyntax = """
            get {
                \(raw: backingName).value
            }
            """
        let setter: AccessorDeclSyntax = """
            nonmutating set {
                \(raw: backingName).value = newValue
            }
            """
        return [getter, setter]
    }

    func peers(of node: AttributeSyntax, _ declaration: some DeclSyntaxProtocol) throws -> [DeclSyntax] {
        let identifier = try identifier(of: declaration)
        guard let binding = declaration.as(VariableDeclSyntax.self)?.bindings.first,
              let typeAnnotation = binding.typeAnnotation?.type else {
            throw MacroError.message("@\(name) requires explicit type annotation")
        }
        let typeName = typeAnnotation.trimmedDescription

        // @Name("key") or @Name("key", store: .custom)
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              firstArg.label == nil else {
            throw MacroError.message("@\(name) requires a string key as first argument")
        }
        let keyExpr = firstArg.expression.trimmedDescription
        let storeExpr = arguments.dropFirst().first { $0.label?.text == "store" }?.expression.trimmedDescription ?? ".shared"

        let defaultExpr: String
        if let initializer = binding.initializer {
            defaultExpr = initializer.value.trimmedDescription
        } else if typeName.hasSuffix("?") {
            defaultExpr = "nil"
        } else {
            throw MacroError.message("@\(name) requires a default value for non-optional types")
        }

        let backingName = "_\(identifier)_stor"
        let backingDecl: DeclSyntax = """
            private let \(raw: backingName) = StorableBackend<\(raw: typeName)>(key: \(raw: keyExpr), default: \(raw: defaultExpr), \(raw: storeLabel): \(raw: storeExpr))
            """
        let projection: DeclSyntax = """
            var $\(raw: identifier): StorableBackend<\(raw: typeName)>.Binding {
                \(raw: backingName).binding
            }
            """
        return [backingDecl, projection]
    }

    private func identifier(of declaration: some DeclSyntaxProtocol) throws -> String {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            throw MacroError.message("@\(name) can only be applied to stored properties")
        }
        return identifier
    }
}

// MARK: - MacroError

enum MacroError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }
}
