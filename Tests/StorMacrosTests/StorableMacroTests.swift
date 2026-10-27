//
//  StorableMacroTests.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import StorMacros

@Suite("StorableMacro Tests")
struct StorableMacroTests {
    let testMacros: [String: any Macro.Type] = [
        "Storable": StorableMacro.self,
        "Keychain": KeychainMacro.self,
    ]

    @Test("Expands property with default value")
    func expandsWithDefault() {
        assertMacroExpansion(
            """
            struct Settings {
                @Storable("theme") var theme: String = "light"
            }
            """,
            expandedSource: """
            struct Settings {
                var theme: String {
                    get {
                        _theme_stor.value
                    }
                    nonmutating set {
                        _theme_stor.value = newValue
                    }
                }

                private let _theme_stor = StorableBackend<String>(key: "theme", default: "light", store: .shared)

                var $theme: StorableBackend<String>.Binding {
                    _theme_stor.binding
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("Expands optional property without default")
    func expandsOptional() {
        assertMacroExpansion(
            """
            @Storable("token") var token: String?
            """,
            expandedSource: """
            var token: String? {
                get {
                    _token_stor.value
                }
                nonmutating set {
                    _token_stor.value = newValue
                }
            }

            private let _token_stor = StorableBackend<String?>(key: "token", default: nil, store: .shared)

            var $token: StorableBackend<String?>.Binding {
                _token_stor.binding
            }
            """,
            macros: testMacros
        )
    }

    @Test("Expands with custom store")
    func expandsWithCustomStore() {
        assertMacroExpansion(
            """
            @Storable("count", store: .custom) var count: Int = 0
            """,
            expandedSource: """
            var count: Int {
                get {
                    _count_stor.value
                }
                nonmutating set {
                    _count_stor.value = newValue
                }
            }

            private let _count_stor = StorableBackend<Int>(key: "count", default: 0, store: .custom)

            var $count: StorableBackend<Int>.Binding {
                _count_stor.binding
            }
            """,
            macros: testMacros
        )
    }

    @Test("@Keychain backs the property with a KeychainStore")
    func keychainExpandsWithKeychainStore() {
        assertMacroExpansion(
            """
            @Keychain("user.session.accessToken") var accessToken: String = ""
            @Keychain("sharedToken", store: .group) var sharedToken: String?
            """,
            expandedSource: """
            var accessToken: String {
                get {
                    _accessToken_stor.value
                }
                nonmutating set {
                    _accessToken_stor.value = newValue
                }
            }

            private let _accessToken_stor = StorableBackend<String>(key: "user.session.accessToken", default: "", keychain: .shared)

            var $accessToken: StorableBackend<String>.Binding {
                _accessToken_stor.binding
            }
            var sharedToken: String? {
                get {
                    _sharedToken_stor.value
                }
                nonmutating set {
                    _sharedToken_stor.value = newValue
                }
            }

            private let _sharedToken_stor = StorableBackend<String?>(key: "sharedToken", default: nil, keychain: .group)

            var $sharedToken: StorableBackend<String?>.Binding {
                _sharedToken_stor.binding
            }
            """,
            macros: testMacros
        )
    }

    @Test("A non-optional property without a default value is rejected")
    func rejectsMissingDefault() {
        assertMacroExpansion(
            """
            @Keychain("pin") var pin: String
            """,
            expandedSource: """
            var pin: String {
                get {
                    _pin_stor.value
                }
                nonmutating set {
                    _pin_stor.value = newValue
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Keychain requires a default value for non-optional types", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }
}
