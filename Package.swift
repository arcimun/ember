// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DictationService",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "DictationService",
            targets: ["DictationService"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DictationService",
            path: "Sources",
            resources: [
                .copy("../Resources/overlay.html")
            ]
        )
    ]
)
