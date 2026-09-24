import Testing
import Foundation
@testable import StarHubTHCore

/// Où va un fichier de langue livré sans son dossier `i18n` (2026-09-24).
struct LocaleFilePlacementTests {
    private let parc = ["[CP] Jakk's Quinn", "[CP] Nyapu Style Jakks Quinn", "[CP] Mizu's Goose",
                        "PC's Rattan Furniture", "Evelyn Expansion"]

    /// L'archive réelle de « Jakkk's Quinn - Patch FR » (Nexus 41740) : un
    /// dossier de présentation et un `fr.json`. Le fichier va dans `i18n/`.
    @Test func bareLocaleFileUnderAWrapperGoesToI18n() {
        let outcome = ManifestlessArchive.classify(paths: ["Patch FR/fr.json"],
                                                   installedFolderNames: parc)
        guard case .needsHost(_, let kind, let entries) = outcome else {
            Issue.record("attendu : hôte à désigner"); return
        }
        #expect(kind == .translation)
        #expect(entries.map(\.destination) == ["i18n/fr.json"])
    }

    @Test func bareLocaleFileWithoutFolderGoesToI18n() {
        let outcome = ManifestlessArchive.classify(paths: ["fr.json"], installedFolderNames: parc)
        guard case .needsHost(_, let kind, let entries) = outcome else {
            Issue.record("attendu : hôte à désigner"); return
        }
        #expect(kind == .translation)
        #expect(entries.map(\.destination) == ["i18n/fr.json"])
    }

    /// Un `config.json` voisin : ce n'est pas un lot de langue, rien ne bouge.
    @Test func nonLocaleNeighbourLeavesTheArchiveAlone() {
        let entries = [ManifestlessArchive.Entry(source: "fr.json", destination: "fr.json"),
                       ManifestlessArchive.Entry(source: "config.json", destination: "config.json")]
        #expect(ManifestlessArchive.relocatingBareLocaleFiles(entries) == entries)
        #expect(ManifestlessArchive.isLocaleFileName("pt-BR.json"))
        #expect(ManifestlessArchive.isLocaleFileName("default.json"))
        #expect(!ManifestlessArchive.isLocaleFileName("content.json"))
    }

    /// Le « s » d'un possessif ne rapproche plus Jakk's Quinn des mods de
    /// Mizu ou de PC.
    @Test func possessiveSDoesNotMatchUnrelatedMods() {
        let candidates = ManifestlessArchive.candidates(for: "Jakkk's Quinn - Patch FR", among: parc)
        // Les deux dossiers Quinn, et eux seuls ; les départager est l'affaire
        // du lien avec le téléchargement (`FrenchTranslationSweep.hosts`).
        #expect(Set(candidates) == ["[CP] Jakk's Quinn", "[CP] Nyapu Style Jakks Quinn"])
        #expect(!candidates.contains("[CP] Mizu's Goose"))
        #expect(!candidates.contains("PC's Rattan Furniture"))
    }

    // MARK: - Rangement de l'hôte

    private func plan(_ destination: String) -> ManifestlessArchive.Plan {
        .init(hostFolderName: "Host", kind: .translation,
              entries: [.init(source: "Patch FR/fr.json", destination: destination)])
    }

    /// Hôte rangé par sous-dossiers, avec un `Fr` existant (East Scarp) : on
    /// y dépose, casse comprise. À plat, SMAPI ignorerait tous les dossiers.
    @Test func subfolderHostReceivesTheFileInItsLocaleFolder() {
        let host = ManifestlessArchive.I18nLayout(directories: ["Default", "Fr"], rootJSONFiles: [])
        let adapted = ManifestlessArchive.adaptingLocaleLayout(plan("i18n/fr.json"), to: host)
        #expect(adapted.entries.map(\.destination) == ["i18n/Fr/fr.json"])
    }

    @Test func subfolderHostWithoutFrenchFolderGetsOne() {
        let host = ManifestlessArchive.I18nLayout(directories: ["default"], rootJSONFiles: [])
        let adapted = ManifestlessArchive.adaptingLocaleLayout(plan("i18n/fr.json"), to: host)
        #expect(adapted.entries.map(\.destination) == ["i18n/fr/fr.json"])
    }

    /// Hôte à plat (Evelyn Expansion), ou sans `i18n` : rien ne change.
    @Test func flatOrEmptyHostKeepsTheFlatFile() {
        let flat = ManifestlessArchive.I18nLayout(directories: [], rootJSONFiles: ["default.json"])
        let none = ManifestlessArchive.I18nLayout(directories: [], rootJSONFiles: [])
        #expect(ManifestlessArchive.adaptingLocaleLayout(plan("i18n/fr.json"), to: flat)
                    .entries.map(\.destination) == ["i18n/fr.json"])
        #expect(ManifestlessArchive.adaptingLocaleLayout(plan("i18n/fr.json"), to: none)
                    .entries.map(\.destination) == ["i18n/fr.json"])
    }

    @Test func layoutIsReadFromDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("i18n-layout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("i18n/Fr"),
                                                withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("i18n/Fr/Dialogue.json"))
        try Data("x".utf8).write(to: root.appendingPathComponent("i18n/Lisez-moi.txt"))
        let layout = ManifestlessArchive.I18nLayout.read(modDirectory: root)
        #expect(layout == .init(directories: ["Fr"], rootJSONFiles: []))
    }

    /// L'archive venue d'un lien Nexus retrouve le mod pour lequel la page a
    /// été trouvée.
    @Test func sweepEntriesNameTheHostOfADownloadedTranslation() {
        let hit = NexusModSearch.Hit(modId: 41740, name: "Jakkk's Quinn - Patch FR", version: "1.1.8",
                                     updatedAt: nil, categoryName: "", uploader: "", adultContent: true)
        let entries = ["[CP] Jakk's Quinn": FrenchTranslationSweep.Entry(hits: [hit], searchedAt: Date()),
                       "Other": FrenchTranslationSweep.Entry(hits: [], searchedAt: Date())]
        #expect(FrenchTranslationSweep.hosts(ofTranslation: 41740, in: entries) == ["[CP] Jakk's Quinn"])
        #expect(FrenchTranslationSweep.hosts(ofTranslation: 1, in: entries).isEmpty)
    }
}
