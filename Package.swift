// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftKHD",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.5.0")),
    ],
    targets: [
        .target(
            name: "CHelpers",
            path: "Sources/SwiftKHD/CHelpers",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "SwiftKHD",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CHelpers",
            ],
            path: "Sources/SwiftKHD",
            exclude: ["CHelpers"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "SwiftKHDTests",
            dependencies: ["SwiftKHD"],
            path: "Tests/SwiftKHDTests",
            resources: [
                .copy("testdata"),
            ]
        ),
    ]
)
