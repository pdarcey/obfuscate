// swift-tools-version: 6.2
//
// ObfuscateKit: the core logic of the obfuscate command-line tool, in a package so it
// can be unit tested (a test target can't import an executable target).
//
// © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

import PackageDescription

let package = Package(
    name: "ObfuscateKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ObfuscateKit", targets: ["ObfuscateKit"])
    ],
    targets: [
        .target(name: "ObfuscateKit"),
        .testTarget(name: "ObfuscateKitTests", dependencies: ["ObfuscateKit"])
    ]
)
