// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InAppDebugKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "InAppDebugKit", targets: ["InAppDebugKit"])
    ],
    targets: [
        .target(
            name: "InAppDebugKit",
            path: "Sources/InAppDebugKit"
        ),
        .testTarget(
            name: "InAppDebugKitTests",
            dependencies: ["InAppDebugKit"],
            path: "Tests/InAppDebugKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
