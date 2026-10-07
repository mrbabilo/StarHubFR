import Foundation
import Testing
@testable import StarHubTHCore

/// Le catalogue des « Extensions principales » des réglages : ce que l'app
/// exige, ce qu'elle recommande, et d'où on l'installe.
@Suite struct AppExtensionsTests {

    private func mod(_ folder: String, id: String, enabled: Bool) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0", author: "",
                description: "", nexusUrl: "", nexusModId: "", isEnabled: enabled,
                dependencies: [], children: nil, isGroup: false)
    }

    @Test func catalogIdsAreUniqueAndGroupedRequiredFirst() {
        let ids = AppExtension.catalog.map { $0.uniqueId.lowercased() }
        #expect(Set(ids).count == ids.count)
        let groups = AppExtension.catalog.map(\.group)
        #expect(groups == groups.sorted { $0 == .requiredByApp && $1 == .common })
        #expect(AppExtension.catalog.contains { $0.group == .common })
    }

    @Test func smapiSourceMatchesTheBulkProtection() {
        // Une ligne « installé par SMAPI » doit désigner exactement les mods
        // que A1-T12 protège — pas un de plus, pas un de moins.
        let smapi = AppExtension.catalog.filter { $0.source == .smapi }.map { $0.uniqueId.lowercased() }
        #expect(Set(smapi) == ModItem.smapiBundledIds.subtracting(["smapi.errorhandler"]))
    }

    @Test func nexusSourcesOpenTheFilesTab() throws {
        let slo = try #require(AppExtension.catalog.first { $0.uniqueId == SloDiagnosticContract.uniqueId })
        #expect(slo.installURL?.absoluteString == "https://www.nexusmods.com/stardewvalley/mods/50153?tab=files")
        let probe = try #require(AppExtension.catalog.first { $0.uniqueId == ModPresence.probeId })
        #expect(probe.source == .app)
        #expect(probe.installURL == nil)
    }

    @Test func presenceFindsAPausedFolderByUniqueIdNotByName() {
        // Sur le parc, CP est en pause (`.ContentPatcher`) et une traduction
        // porte « Content Patcher » dans son nom : seul l'identifiant compte.
        let mods = [mod("ContentPatcherFR", id: "someone.ContentPatcherFR", enabled: true),
                    mod("ContentPatcher", id: "Pathoschild.ContentPatcher", enabled: false)]
        let cp = AppExtension.catalog.first { $0.uniqueId == "Pathoschild.ContentPatcher" }!
        #expect(cp.presence(in: mods) == .paused(folderName: "ContentPatcher", version: "1.0"))
    }
}

extension AppExtensionsTests {
    @Test func everyPurposeKeyExistsInBothLocales() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for locale in ["en", "fr"] {
            let data = try Data(contentsOf: repo.appendingPathComponent("assets/\(locale).json"))
            let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            for ext in AppExtension.catalog {
                #expect(keys[ext.purposeKey] != nil, "\(locale): \(ext.purposeKey)")
            }
        }
    }
}
