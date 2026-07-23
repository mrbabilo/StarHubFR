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
                "SaveManager.swift",
                "Models/InventoryItem.swift",
                "Models/NxmLink.swift",
                "Models/NexusDownloadAPI.swift",
                "Models/ManifestVersionPatcher.swift",
                "L10n.swift",
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
        .testTarget(
            name: "SaveManagerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SaveManagerTests"
        ),
        .testTarget(
            name: "NexusDownloadTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/NexusDownloadTests"
        ),
        .testTarget(
            name: "ManifestVersionPatcherTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ManifestVersionPatcherTests"
        ),
    ]
)
