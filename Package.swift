// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lockLac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LockLacCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "locklac",
            dependencies: ["LockLacCore"]
        ),
        .testTarget(
            name: "LockLacCoreTests",
            dependencies: ["LockLacCore"]
        ),
    ]
)
