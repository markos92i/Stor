// swift-tools-version: 6.3

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
