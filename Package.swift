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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Ember",
            dependencies: ["Sparkle"],
            path: "Sources",
            resources: [
                .copy("../Resources/overlay.html")
            ]
        )
    ]
)
