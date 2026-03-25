// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ember",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "Ember",
            targets: ["Ember"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Ember",
            dependencies: [
                "Sparkle",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources",
            resources: [
                .copy("../Resources/themes")
            ]
        ),
        .testTarget(
            name: "EmberTests",
            path: "Tests/EmberTests"
        )
    ]
)
