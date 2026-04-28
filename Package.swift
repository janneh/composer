// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Composer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Composer", targets: ["ComposerApp"]),
        .library(name: "SymphonyCore", targets: ["SymphonyCore"]),
        .library(name: "SymphonyInterfaces", targets: ["SymphonyInterfaces"]),
        .library(name: "SymphonyLocalStore", targets: ["SymphonyLocalStore"]),
        .library(name: "SymphonyRuntime", targets: ["SymphonyRuntime"])
    ],
    targets: [
        .target(name: "SymphonyCore"),
        .target(
            name: "SymphonyInterfaces",
            dependencies: ["SymphonyCore"]
        ),
        .target(
            name: "SymphonyLocalStore",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .target(
            name: "SymphonyRuntime",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .executableTarget(
            name: "ComposerApp",
            dependencies: [
                "SymphonyCore",
                "SymphonyInterfaces",
                "SymphonyLocalStore",
                "SymphonyRuntime"
            ]
        ),
        .testTarget(
            name: "SymphonyCoreTests",
            dependencies: ["SymphonyCore"]
        )
    ]
)
