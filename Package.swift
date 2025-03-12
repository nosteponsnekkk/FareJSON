// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FareJSON",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FareJSON",
            targets: ["FareJSON"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nosteponsnekkk/SwiftyFare.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FareJSON",
            dependencies: [
                .product(
                    name: "SwiftyFare",
                    package: "SwiftyFare"
                ),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "FareJSONTests",
            dependencies: ["FareJSON"]),
    ]
)
