// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
    targets: [
        .target(
            name: "Stor"),
        .testTarget(
            name: "StorTests",
            dependencies: ["Stor"]
        ),
    ]
)
