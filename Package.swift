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
                "UDKey.swift",
                "ModConfigBackup.swift",
                "ModConfigBackupManager.swift",
                "DictionaryExtensions.swift",
                "ZipModInfo.swift",
                "ModInstallBackup.swift",
                "ModInstallBackupManager.swift",
                "ModZipInstaller.swift",
                "ModFolderRepairer.swift",
                "SaveManager.swift",
                "Models/InventoryItem.swift",
                "Models/NxmLink.swift",
                "Models/NexusDownloadAPI.swift",
                "Models/NexusRequestBuilder.swift",
                "Models/ManifestVersionPatcher.swift",
                "Models/DescriptionBlockParser.swift",
                "Models/ModDependencyParser.swift",
                "Models/DependencyTree.swift",
                "L10n.swift",
                "AppDesignCore.swift",
                "ContrastChecker.swift",
                "Extensions/ModConfigFiles.swift",
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
            name: "ModZipInstallerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModZipInstallerTests"
        ),
        .testTarget(
            name: "ModFolderRepairerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModFolderRepairerTests"
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
            name: "ParseNexusIdTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ParseNexusIdTests"
        ),
        .testTarget(
            name: "ManifestVersionPatcherTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ManifestVersionPatcherTests"
        ),
        .testTarget(
            name: "ModTagTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModTagTests"
        ),
        .testTarget(
            name: "DescriptionBlockTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DescriptionBlockTests"
        ),
        .testTarget(
            name: "ModDependencyParserTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModDependencyParserTests"
        ),
        .testTarget(
            name: "DependencyTreeTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DependencyTreeTests"
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DesignSystemTests"
        ),
    ]
)
