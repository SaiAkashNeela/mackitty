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
            path: "Sources/MoleMate",
            resources: [
                .copy("bg.mp4"),
                .copy("logo.png"),
                .copy("AppIcon.icns")
            ]
        )
    ]
)
