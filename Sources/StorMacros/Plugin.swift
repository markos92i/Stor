//
//  Plugin.swift
//  Stor
//
//  Created by Marcos del Castillo Camacho on 28/09/2026.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct StorMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StorableMacro.self,
    ]
}
