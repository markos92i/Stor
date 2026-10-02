//
//  StorableMacroTests.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import Testing
import SwiftSyntaxMacrosTestSupport
@testable import StorMacros

@Suite("StorableMacro Tests")
struct StorableMacroTests {
    
    let testMacros: [String: any Macro.Type] = [
        "Storable": StorableMacro.self,
    ]
    
    @Test("Expands property with default value")
    func expandsWithDefault() {
        assertMacroExpansion(
            """
            @Observable @MainActor
            final class Settings {
                @Storable("theme") var theme: String = "light"
            }
            """,
            expandedSource: """
            @Observable @MainActor
            final class Settings {
                var theme: String {
                    get {
                        access(keyPath: \\.theme)
                        return _theme_stor.value
                    }
                    set {
                        withMutation(keyPath: \\.theme) {
                            _theme_stor.value = newValue
                        }
                    }
                }

                @ObservationIgnored private var _theme_stor = StorableBackend<String>(key: "theme", default: "light", store: .shared)
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
                    access(keyPath: \\.token)
                    return _token_stor.value
                }
                set {
                    withMutation(keyPath: \\.token) {
                        _token_stor.value = newValue
                    }
                }
            }

            @ObservationIgnored private var _token_stor = StorableBackend<String?>(key: "token", default: nil, store: .shared)
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
                    access(keyPath: \\.count)
                    return _count_stor.value
                }
                set {
                    withMutation(keyPath: \\.count) {
                        _count_stor.value = newValue
                    }
                }
            }

            @ObservationIgnored private var _count_stor = StorableBackend<Int>(key: "count", default: 0, store: .custom)
            """,
            macros: testMacros
        )
    }
}
