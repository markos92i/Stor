//
//  StorableMacro.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

/// `@Storable` transforms a stored property into one backed by `Stor` persistence
/// with automatic SwiftUI reactivity.
///
/// Works in both SwiftUI Views and `@Observable` classes:
///
/// ```swift
/// // In a View
/// struct SettingsView: View {
///     @Storable("theme") var theme: Theme = .system
///     
///     var body: some View {
///         Picker("Theme", selection: $theme) { ... }
///     }
/// }
///
/// // In an @Observable class
/// @Observable @MainActor
/// final class AppState {
///     @Storable("config") var config: Config = .default
/// }
/// ```
///
/// ## How it works
/// - Values are persisted to `Stor` (disk-backed JSON storage)
/// - Reactivity comes from `StorableRegistry`, an `@Observable` singleton
/// - Changes from anywhere (UI or programmatic) propagate to all observers
/// - Thread-safe: programmatic changes from background dispatch to MainActor
///
/// ## Programmatic access
/// Use `Stor` directly for background operations:
/// ```swift
/// // From any context (background task, actor, etc.)
/// await Stor.shared.set("config", newConfig)
/// // All @Storable("config") properties update automatically
/// ```
public struct StorableMacro: AccessorMacro, PeerMacro {
    
    // MARK: - AccessorMacro
    
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            throw MacroError.message("@Storable can only be applied to stored properties")
        }
        
        let backingName = "_\(identifier)_stor"
        
        // Simple accessors that delegate to the backing storage.
        // Reactivity comes from StorableRegistry being @Observable.
        // nonmutating set allows using in static let singletons.
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
    
    // MARK: - PeerMacro
    
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            throw MacroError.message("@Storable can only be applied to stored properties")
        }
        
        // Extract type annotation
        guard let typeAnnotation = binding.typeAnnotation?.type else {
            throw MacroError.message("@Storable requires explicit type annotation")
        }
        let typeName = typeAnnotation.trimmedDescription
        
        // Extract key from macro arguments: @Storable("key") or @Storable("key", store: .custom)
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              firstArg.label == nil else {
            throw MacroError.message("@Storable requires a string key as first argument")
        }
        let keyExpr = firstArg.expression.trimmedDescription
        
        // Check for optional store parameter
        var storeExpr = ".shared"
        for arg in arguments.dropFirst() {
            if arg.label?.text == "store" {
                storeExpr = arg.expression.trimmedDescription
            }
        }
        
        // Extract default value if present
        let defaultExpr: String
        if let initializer = binding.initializer {
            defaultExpr = initializer.value.trimmedDescription
        } else if typeName.hasSuffix("?") {
            defaultExpr = "nil"
        } else {
            throw MacroError.message("@Storable requires a default value for non-optional types")
        }
        
        let backingName = "_\(identifier)_stor"
        
        // Generate backing storage as a simple private let.
        // StorableBackend is Sendable and handles MainActor dispatch internally.
        let backingDecl: DeclSyntax = """
            private let \(raw: backingName) = StorableBackend<\(raw: typeName)>(key: \(raw: keyExpr), default: \(raw: defaultExpr), store: \(raw: storeExpr))
            """
        
        return [backingDecl]
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
