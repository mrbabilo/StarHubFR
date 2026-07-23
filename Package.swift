// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StarHubTHCore",
    platforms: [.macOS(.v14)], // matches Info.plist's LSMinimumSystemVersion
    products: [
        .library(name: "StarHubTHCore", targets: ["StarHubTHCore"]),
    ],
    targets: [
        .target(
            name: "StarHubTHCore",
            path: "StarHubTH",
            sources: [
                "ModItem.swift",
                "ModConfigBackup.swift",
                "ModConfigBackupManager.swift",
                "DictionaryExtensions.swift",
                "ZipModInfo.swift",
                "ModInstallBackup.swift",
                "ModInstallBackupManager.swift",
            ]
        ),
        .testTarget(
            name: "ModConfigBackupManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModConfigBackupManagerTests"
        ),
        .testTarget(
            name: "ModInstallBackupManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModInstallBackupManagerTests"
        ),
    ]
)
