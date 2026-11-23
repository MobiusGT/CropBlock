// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CropBlock",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure Swift engine and math with zero SwiftUI imports, so unit tests run in seconds.
        .target(
            name: "CropBlockKit"
        ),
        .executableTarget(
            name: "CropBlock",
            dependencies: ["CropBlockKit"],
            // App code runs on the main actor by default unless marked nonisolated/@concurrent.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "CropBlockKitTests",
            dependencies: ["CropBlockKit"]
        ),
    ]
)
