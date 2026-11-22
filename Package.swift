// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacKitty",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacKitty", targets: ["MacKitty"])
    ],
    targets: [
        .executableTarget(
            name: "MacKitty",
            path: "Sources/MacKitty",
            resources: [
                .copy("bg.mp4"),
                .copy("logo.png"),
                .copy("AppIcon.icns"),
                .copy("tray_icon.png")
            ]
        ),
        .testTarget(
            name: "MacKittyTests",
            dependencies: ["MacKitty"],
            path: "Tests/MacKittyTests"
        )
    ]
)
