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
                "Models/SmapiLogDiagnostics.swift",
                "Models/LogNoise.swift",
                "Models/ModErrorHistory.swift",
                "Models/ManifestJSON.swift",
                "Models/BisectionEvidence.swift",
                "Models/BisectionSession.swift",
                "Models/BisectionSnapshot.swift",
                "Models/ModFocusResolver.swift",
                "Models/LogEntry.swift",
                "Models/SmapiLogParser.swift",
                "Models/DroppedContentRecognizer.swift",
                "Models/TranslationBackupFinder.swift",
                "Models/TranslationTokens.swift",
                "Models/I18nFileDecoder.swift",
                "Models/I18nOutline.swift",
                "Models/I18nLenientParser.swift",
                "Models/I18nLocaleResolver.swift",
                "Models/TranslationCoverage.swift",
                "Models/TranslationDiffGroups.swift",
                "Models/TranslationFreshness.swift",
                "Models/TranslationBaseline.swift",
                "Models/ThaiTranslationTable.swift",
                "NexusUpdateChecker.swift",
                "Models/NexusUpdateConsolidation.swift",
                "Models/InstalledModRegistry.swift",
                "Models/SaveTree.swift",
                "Models/OSJunk.swift",
                "Models/ModDependencyStatus.swift",
                "Models/CoreModSlot.swift",
                "Models/XMLEntities.swift",
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
            name: "I18nOutlineTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/I18nOutlineTests"
        ),
        .testTarget(
            name: "I18nDecodingTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/I18nDecodingTests"
        ),
        .testTarget(
            name: "TranslationTokenTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationTokenTests"
        ),
        .testTarget(
            name: "TranslationBackupTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationBackupTests"
        ),
        .testTarget(
            name: "DroppedContentTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DroppedContentTests"
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
            name: "SmapiLogDiagnosticsTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SmapiLogDiagnosticsTests"
        ),
        .testTarget(
            name: "LogNoiseTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LogNoiseTests"
        ),
        .testTarget(
            name: "ModErrorHistoryTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModErrorHistoryTests"
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DesignSystemTests"
        ),
        .testTarget(
            name: "BisectionEvidenceTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/BisectionEvidenceTests"
        ),
        .testTarget(
            name: "LogAttributionTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LogAttributionTests"
        ),
        .testTarget(
            name: "ManifestJSONTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ManifestJSONTests"
        ),
        .testTarget(
            name: "BisectionSessionTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/BisectionSessionTests"
        ),
        .testTarget(
            name: "BisectionSnapshotTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/BisectionSnapshotTests"
        ),
        .testTarget(
            name: "ModFocusResolverTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModFocusResolverTests"
        ),
        .testTarget(
            name: "CoreModSlotTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/CoreModSlotTests"
        ),
        .testTarget(
            name: "ModDependencyStatusTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModDependencyStatusTests"
        ),
        .testTarget(
            name: "OSJunkTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/OSJunkTests"
        ),
        .testTarget(
            name: "XMLEntitiesTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/XMLEntitiesTests"
        ),
        .testTarget(
            name: "SaveTreeTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SaveTreeTests"
        ),
        .testTarget(
            name: "ModItemFlatteningTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModItemFlatteningTests"
        ),
        .testTarget(
            name: "InstalledModRegistryTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/InstalledModRegistryTests"
        ),
        .testTarget(
            name: "NexusUpdateConsolidationTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/NexusUpdateConsolidationTests"
        ),
        .testTarget(
            name: "VersionCompareTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/VersionCompareTests"
        ),
        .testTarget(
            name: "ThaiTranslationTableTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ThaiTranslationTableTests"
        ),
        .testTarget(
            name: "I18nCoverageTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/I18nCoverageTests"
        ),
        .testTarget(
            name: "SmapiLogParserTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SmapiLogParserTests"
        ),
        .testTarget(
            name: "BisectionCopyTests",
            path: "Tests/BisectionCopyTests"
        ),
    ]
)
