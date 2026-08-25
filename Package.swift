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
                "Models/NexusRateLimitGate.swift",
                "Models/NexusQuota.swift",
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
                "Models/TranslationBatchPlanner.swift",
                "Models/TranslationBaselineRules.swift",
                "Models/ThaiTranslationTable.swift",
                "NexusUpdateChecker.swift",
                "Models/NexusUpdateConsolidation.swift",
                "Models/NexusInstallIdRecording.swift",
                "Models/ModVersionAnchor.swift",
                "Models/ModVersionAnchorRules.swift",
                "Models/ModVersionAnchorStore.swift",
                "Models/InstalledModRegistry.swift",
                "Models/SmapiUpdateRequest.swift",
                "Models/SmapiUpdateResponse.swift",
                "Models/ManifestVersionReader.swift",
                "Models/SaveTree.swift",
                "Models/OSJunk.swift",
                "Models/ModsFolderSizer.swift",
                "Models/FavoriteResolution.swift",
                "Models/ModDependencyStatus.swift",
                "Models/CoreModSlot.swift",
                "Models/XMLEntities.swift",
                "L10n.swift",
                "AppDesignCore.swift",
                "ContrastChecker.swift",
                "Models/OrderedJSONWriter.swift",
                "Models/TranslationTokenCheck.swift",
                "Models/TranslationComponentResolver.swift",
                "Models/TranslationDocument.swift",
                "Models/TranslationFileStore.swift",
                "Models/TranslationWaiver.swift",
                "Models/LzxdBitstream.swift",
                "Models/LzxdWindow.swift",
                "Models/LzxdTree.swift",
                "Models/LzxdDecoder.swift",
                "Models/XnbStringDictionaryReader.swift",
                "Models/GlossaryBuilder.swift",
                "Models/Glossary.swift",
                "Models/GlossaryStore.swift",
                "Models/LocalLLMEndpoint.swift",
                "Models/LocalLLMClient.swift",
                "Models/LocalModelAdvisor.swift",
                "Models/OllamaCapabilities.swift",
                "Models/TranslationLot.swift",
                "Models/TranslationLotImport.swift",
                "Models/TokenShield.swift",
                "Models/DeepLClient.swift",
                "Models/TranslationEngine.swift",
                "Models/KeychainSecret.swift",
                "Models/DeepLDesktop.swift",
                "Models/TranslationFragment.swift",
                "Models/FolderDigest.swift",
                "Models/BackupBrowser.swift",
                "Models/ModProfile.swift",
                "Models/ProfileFactory.swift",
                "Models/ProfileDiagnostics.swift",
                "Models/FileRecovery.swift",
                "Models/TranslationRecoveryDiff.swift",
                "Extensions/ModConfigFiles.swift",
            ]
        ),
        .testTarget(
            name: "TranslationWaiverTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationWaiverTests"
        ),
        .testTarget(
            name: "TranslationFileStoreTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationFileStoreTests"
        ),
        .testTarget(
            name: "TranslationDocumentTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationDocumentTests"
        ),
        .testTarget(
            name: "TranslationComponentResolverTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationComponentResolverTests"
        ),
        .testTarget(
            name: "TranslationTokenCheckTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationTokenCheckTests"
        ),
        .testTarget(
            name: "OrderedJSONWriterTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/OrderedJSONWriterTests"
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
            name: "NexusRateLimitTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/NexusRateLimitTests"
        ),
        .testTarget(
            name: "NexusQuotaTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/NexusQuotaTests"
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
            name: "FavoriteResolutionTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/FavoriteResolutionTests"
        ),
        .testTarget(
            name: "ModsFolderSizerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModsFolderSizerTests"
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
            name: "NexusInstallIdRecordingTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/NexusInstallIdRecordingTests"
        ),
        .testTarget(
            name: "ModVersionAnchorTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModVersionAnchorTests"
        ),
        .testTarget(
            name: "ModVersionAnchorRulesTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModVersionAnchorRulesTests"
        ),
        .testTarget(
            name: "ModVersionAnchorStoreTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ModVersionAnchorStoreTests"
        ),
        .testTarget(
            name: "VersionCompareTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/VersionCompareTests"
        ),
        .testTarget(
            name: "SmapiUpdateRequestTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SmapiUpdateRequestTests"
        ),
        .testTarget(
            name: "ManifestVersionReaderTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ManifestVersionReaderTests"
        ),
        .testTarget(
            name: "SmapiUpdateResponseTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/SmapiUpdateResponseTests"
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
        .testTarget(
            name: "LzxdBitstreamTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LzxdBitstreamTests"
        ),
        .testTarget(
            name: "LzxdWindowTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LzxdWindowTests"
        ),
        .testTarget(
            name: "LzxdTreeTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LzxdTreeTests"
        ),
        .testTarget(
            name: "LzxdDecoderTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LzxdDecoderTests"
        ),
        .testTarget(
            name: "XnbStringDictionaryReaderTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/XnbStringDictionaryReaderTests"
        ),
        .testTarget(
            name: "XnbOracleTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/XnbOracleTests"
        ),
        .testTarget(
            name: "GlossaryBuilderTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/GlossaryBuilderTests"
        ),
        .testTarget(
            name: "OllamaCapabilitiesTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/OllamaCapabilitiesTests"
        ),
        .testTarget(
            name: "LocalModelAdvisorTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LocalModelAdvisorTests"
        ),
        .testTarget(
            name: "GlossaryMatchingTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/GlossaryMatchingTests"
        ),
        .testTarget(
            name: "GlossaryStoreTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/GlossaryStoreTests"
        ),
        .testTarget(
            name: "TranslationBaselineTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationBaselineTests"
        ),
        .testTarget(
            name: "TranslationBatchPlannerTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationBatchPlannerTests"
        ),
        .testTarget(
            name: "LocalLLMEndpointTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LocalLLMEndpointTests"
        ),
        .testTarget(
            name: "LocalLLMClientTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/LocalLLMClientTests"
        ),
        .testTarget(
            name: "TranslationLotTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationLotTests"
        ),
        .testTarget(
            name: "TranslationLotImportTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationLotImportTests"
        ),
        .testTarget(
            name: "BackupBrowserTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/BackupBrowserTests"
        ),
        .testTarget(
            name: "ProfileFactoryTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ProfileFactoryTests"
        ),
        .testTarget(
            name: "ProfileDiagnosticsTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/ProfileDiagnosticsTests"
        ),
        .testTarget(
            name: "FileRecoveryTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/FileRecoveryTests"
        ),
        .testTarget(
            name: "TranslationRecoveryTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationRecoveryTests"
        ),
        .testTarget(
            name: "FolderDigestTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/FolderDigestTests"
        ),
        .testTarget(
            name: "DeepLLiveTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DeepLLiveTests"
        ),
        .testTarget(
            name: "TranslationFragmentTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationFragmentTests"
        ),
        .testTarget(
            name: "DeepLDesktopTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DeepLDesktopTests"
        ),
        .testTarget(
            name: "KeychainSecretTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/KeychainSecretTests"
        ),
        .testTarget(
            name: "TranslationEngineTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TranslationEngineTests"
        ),
        .testTarget(
            name: "DeepLClientTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/DeepLClientTests"
        ),
        .testTarget(
            name: "TokenShieldTests",
            dependencies: ["StarHubTHCore"],
            path: "Tests/TokenShieldTests"
        ),
    ]
)
