// swift-tools-version: 5.9
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "Composer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Composer", targets: ["ComposerApp"]),
        .executable(name: "composerctl", targets: ["ComposerCLI"]),
        .library(name: "ComposerStorage", targets: ["ComposerStorage"]),
        .library(name: "SymphonyCore", targets: ["SymphonyCore"]),
        .library(name: "SymphonyInterfaces", targets: ["SymphonyInterfaces"]),
        .library(name: "SymphonyLocalStore", targets: ["SymphonyLocalStore"]),
        .library(name: "SymphonySQLiteStore", targets: ["SymphonySQLiteStore"]),
        .library(name: "SymphonyRuntime", targets: ["SymphonyRuntime"]),
        .library(name: "SymphonyWorkflow", targets: ["SymphonyWorkflow"]),
        .library(name: "SymphonyWorkspace", targets: ["SymphonyWorkspace"]),
        .library(name: "SymphonyCodexAgent", targets: ["SymphonyCodexAgent"]),
        .library(name: "SymphonyClaudeAgent", targets: ["SymphonyClaudeAgent"])
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
            name: "SymphonySQLiteStore",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "SymphonyRuntime",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .target(
            name: "SymphonyWorkflow",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .target(
            name: "SymphonyWorkspace",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .target(
            name: "SymphonyCodexAgent",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .target(
            name: "SymphonyClaudeAgent",
            dependencies: ["SymphonyCore", "SymphonyInterfaces"]
        ),
        .target(
            name: "ComposerStorage",
            dependencies: [
                "SymphonyCore",
                "SymphonyInterfaces",
                "SymphonyLocalStore",
                "SymphonySQLiteStore"
            ]
        ),
        .executableTarget(
            name: "ComposerApp",
            dependencies: [
                "ComposerStorage",
                "SymphonyCore",
                "SymphonyInterfaces",
                "SymphonyRuntime",
                "SymphonyWorkflow"
            ]
        ),
        .testTarget(
            name: "ComposerAppTests",
            dependencies: ["ComposerApp", "ComposerStorage", "SymphonyWorkflow"]
        ),
        .executableTarget(
            name: "ComposerCLI",
            dependencies: [
                "ComposerStorage",
                "SymphonyCore",
                "SymphonyInterfaces"
            ]
        ),
        .testTarget(
            name: "SymphonyCoreTests",
            dependencies: ["SymphonyCore"]
        ),
        .testTarget(
            name: "SymphonyRuntimeTests",
            dependencies: ["SymphonyCore", "SymphonyInterfaces", "SymphonyRuntime"]
        ),
        .testTarget(
            name: "SymphonySQLiteStoreTests",
            dependencies: ["SymphonyCore", "SymphonySQLiteStore"]
        ),
        .testTarget(
            name: "SymphonyWorkflowTests",
            dependencies: ["SymphonyCore", "SymphonyWorkflow"]
        ),
        .testTarget(
            name: "SymphonyWorkspaceTests",
            dependencies: ["SymphonyCore", "SymphonyWorkspace"]
        ),
        .testTarget(
            name: "SymphonyCodexAgentTests",
            dependencies: ["SymphonyCore", "SymphonyCodexAgent"]
        ),
        .testTarget(
            name: "SymphonyClaudeAgentTests",
            dependencies: ["SymphonyCore", "SymphonyClaudeAgent"]
        ),
        .testTarget(
            name: "ComposerStorageTests",
            dependencies: ["ComposerStorage", "SymphonyCore"]
        )
    ]
)
