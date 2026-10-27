// swift-tools-version: 6.4

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Stor",
    platforms: [
        .macOS(.v15), .iOS(.v18),
    ],
    products: [
        .library(
            name: "Stor",
            targets: ["Stor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/markos92i/Logy.git", from: "1.0.1"),
    ],
    targets: [
        // Macro implementation (compiler plugin)
        .macro(
            name: "StorMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        
        // Main library
        .target(
            name: "Stor",
            dependencies: [
                "StorMacros",
                .product(name: "Logy", package: "Logy"),
            ]
        ),
        
        // Tests
        .testTarget(
            name: "StorTests",
            dependencies: [
                "Stor",
                .product(name: "Logy", package: "Logy"),
            ]
        ),
        .testTarget(
            name: "StorMacrosTests",
            dependencies: [
                "StorMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
