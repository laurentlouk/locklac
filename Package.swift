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
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "locklac",
            dependencies: ["LockLacCore"],
            exclude: ["Info.plist"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(
            name: "LockLacCoreTests",
            dependencies: ["LockLacCore"]
        ),
    ]
)
