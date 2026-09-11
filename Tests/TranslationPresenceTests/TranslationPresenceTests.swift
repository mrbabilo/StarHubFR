import Foundation
import Testing
@testable import StarHubTHCore

/// Ce que le parc sait d'une traduction posée : y en a-t-il une, et en
/// existe-t-il une version plus récente.
///
/// Les deux règles vivaient **en double exemplaire** dans le ViewModel — la
/// mise à jour pour les traductions et pour les greffes, la présence à côté de
/// `I18nLocaleResolver` qui la portait déjà. Deux copies d'une même règle
/// divergent à la première retouche.
struct TranslationPresenceTests {

    private let installedAt = Date(timeIntervalSince1970: 1_600_000_000)
    private var older: Date { installedAt.addingTimeInterval(-86_400) }
    private var newer: Date { installedAt.addingTimeInterval(86_400) }

    private func hit(_ modId: Int, updatedAt: Date?) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: modId, name: "Traduction", version: "1.0",
                           updatedAt: updatedAt, categoryName: "Translations",
                           uploader: "someone", adultContent: false)
    }

    private func entry(nexusModId: Int, updatedAt: Date?) -> InstalledTranslation {
        InstalledTranslation(hostFolderName: "SVE", nexusModId: nexusModId,
                             nexusName: "Traduction", version: "1.0",
                             updatedAt: updatedAt, installedAt: installedAt,
                             files: [], replacedFiles: [:])
    }

    // MARK: - Une version plus récente existe-t-elle ?

    @Test func aMoreRecentHitOfTheSamePageIsTheUpdate() {
        let found = TranslationPresence.update(for: entry(nexusModId: 42, updatedAt: installedAt),
                                               amongAvailable: [],
                                               andInstalled: [hit(42, updatedAt: newer)])
        #expect(found?.modId == 42)
    }

    @Test func theUpdateIsFoundInTheHalfThatWasTakenOutOfTheProposals() {
        // **La subtilité du domaine** : le résultat qui porte la mise à jour
        // est par nature celui qu'on a retiré des propositions, puisqu'il
        // correspond à ce qui est déjà en place. Ne regarder que les
        // propositions faisait disparaître la pastille de mise à jour.
        let entry = entry(nexusModId: 42, updatedAt: installedAt)
        let onlyInProposals = TranslationPresence.update(for: entry,
                                                         amongAvailable: [hit(42, updatedAt: newer)],
                                                         andInstalled: [])
        let onlyInInstalled = TranslationPresence.update(for: entry, amongAvailable: [],
                                                         andInstalled: [hit(42, updatedAt: newer)])
        #expect(onlyInProposals?.modId == 42)
        #expect(onlyInInstalled?.modId == 42)
    }

    @Test func aHitOfTheSameDateIsNotAnUpdate() {
        let found = TranslationPresence.update(for: entry(nexusModId: 42, updatedAt: installedAt),
                                               amongAvailable: [hit(42, updatedAt: installedAt)],
                                               andInstalled: [])
        #expect(found == nil)
    }

    @Test func anOlderHitIsNotAnUpdate() {
        let found = TranslationPresence.update(for: entry(nexusModId: 42, updatedAt: installedAt),
                                               amongAvailable: [hit(42, updatedAt: older)],
                                               andInstalled: [])
        #expect(found == nil)
    }

    @Test func aMoreRecentHitOfAnotherPageIsNotTheUpdate() {
        let found = TranslationPresence.update(for: entry(nexusModId: 42, updatedAt: installedAt),
                                               amongAvailable: [hit(99, updatedAt: newer)],
                                               andInstalled: [])
        #expect(found == nil)
    }

    @Test func aLineWithoutANexusPageCanNeverHaveAnUpdate() {
        // Sur un compte gratuit tout s'installe à la main, donc sans
        // identifiant : la ligne attend un rattachement, elle ne prétend pas
        // être à jour.
        let found = TranslationPresence.update(for: entry(nexusModId: 0, updatedAt: installedAt),
                                               amongAvailable: [hit(0, updatedAt: newer)],
                                               andInstalled: [])
        #expect(found == nil)
    }

    @Test func anUndatedDepositIsNeverDeclaredOutdated() {
        // `isNewer` refuse de conclure sans les deux dates : annoncer une mise
        // à jour sur une ligne dont on ignore l'âge la ferait clignoter sans
        // fin.
        let found = TranslationPresence.update(for: entry(nexusModId: 42, updatedAt: nil),
                                               amongAvailable: [hit(42, updatedAt: newer)],
                                               andInstalled: [])
        #expect(found == nil)
    }

    // MARK: - Y a-t-il du français sur le disque ?

    private func modFixture(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("presence-\(UUID().uuidString)", isDirectory: true)
        for relative in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func layoutACountsAsTranslated() throws {
        let mod = try modFixture(["i18n/default.json", "i18n/fr.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationPresence.hasFrench(inModDirectory: mod))
    }

    @Test func layoutBCountsAsTranslated() throws {
        // Forme réelle (`.Merchant`, `East Scarp NPCs`…) : ne lire que
        // `fr.json` afficherait « pas de traduction » sur un mod traduit.
        let mod = try modFixture(["i18n/default/dialogue.json", "i18n/fr/dialogue.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(TranslationPresence.hasFrench(inModDirectory: mod))
    }

    @Test func anotherLanguageIsNotFrench() throws {
        let mod = try modFixture(["i18n/default.json", "i18n/de.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(!TranslationPresence.hasFrench(inModDirectory: mod))
    }

    @Test func aModWithoutAnI18nDirectoryIsNotTranslated() throws {
        let mod = try modFixture(["manifest.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(!TranslationPresence.hasFrench(inModDirectory: mod))
    }

    @Test func aFrenchSubdirectoryShadowedByTheRootDoesNotCount() throws {
        // **La règle que la copie du ViewModel ignorait.** Un seul `.json` à
        // la racine suffit à faire ignorer TOUS les sous-dossiers par SMAPI :
        // ce `fr/` n'est jamais servi, l'annoncer comme une traduction
        // présente ferait attendre un français que le jeu ne chargera pas.
        // Aucun mod du parc n'est dans ce cas (mesuré le 2026-09-11).
        let mod = try modFixture(["i18n/default.json", "i18n/en.json", "i18n/fr/dialogue.json"])
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(!TranslationPresence.hasFrench(inModDirectory: mod))
    }

    @Test func anEmptyFrenchSubdirectoryIsNotATranslation() throws {
        let mod = try modFixture(["i18n/default/dialogue.json"])
        let empty = mod.appendingPathComponent("i18n/fr", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mod) }
        #expect(!TranslationPresence.hasFrench(inModDirectory: mod))
    }
}
