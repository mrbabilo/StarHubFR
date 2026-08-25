import Testing
import Foundation
@testable import StarHubTHCore

struct InstalledTranslationTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034)

    private func translation(host: String = "Parchment", modId: Int = 50233,
                             version: String = "1.1.0", updatedAt: Date? = nil,
                             files: [String] = ["i18n/fr.json"],
                             replaced: [String: String] = [:]) -> InstalledTranslation {
        InstalledTranslation(hostFolderName: host, nexusModId: modId,
                             nexusName: "Parchment - Fishing Log - Francais",
                             version: version, updatedAt: updatedAt ?? t0,
                             installedAt: t0, files: files, replacedFiles: replaced)
    }

    @Test func aTranslationIsFoundBackByItsHost() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation())
        #expect(registry.translation(forHost: "Parchment")?.nexusModId == 50233)
        #expect(registry.translation(forHost: "Autre") == nil)
    }

    /// Une seule traduction par mod : la seconde recouvrirait la première sur
    /// le disque, et on ne saurait plus quoi rendre en désinstallant.
    @Test func recordingASecondTranslationReplacesTheFirst() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(modId: 1))
        registry.record(translation(modId: 2))
        #expect(registry.byHost.count == 1)
        #expect(registry.translation(forHost: "Parchment")?.nexusModId == 2)
    }

    /// Oublier rend ce qu'on savait : c'est cette valeur qui dit quels fichiers
    /// retirer et lesquels remettre en place.
    @Test func forgettingHandsBackWhatWasKnown() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(files: ["i18n/fr.json", "assets/x.png"],
                                    replaced: ["i18n/fr.json": "Backups/…/fr.json"]))
        let forgotten = registry.forget(host: "Parchment")
        #expect(forgotten?.files == ["i18n/fr.json", "assets/x.png"])
        #expect(forgotten?.replacedFiles["i18n/fr.json"] == "Backups/…/fr.json")
        #expect(registry.translation(forHost: "Parchment") == nil)
    }

    @Test func forgettingSomethingUnknownIsHarmless() {
        var registry = InstalledTranslationRegistry()
        #expect(registry.forget(host: "Jamais vu") == nil)
    }

    /// **Sur les dates, jamais sur les numéros de version.** Mesuré sur des
    /// traductions réelles : beaucoup reprennent le numéro du mod traduit, ou
    /// ne le bougent pas d'une version à l'autre.
    @Test func anUpdateIsJudgedOnDates() {
        let installed = t0
        #expect(InstalledTranslationRegistry.isNewer(t0.addingTimeInterval(86400), than: installed))
        #expect(!InstalledTranslationRegistry.isNewer(t0, than: installed))
        #expect(!InstalledTranslationRegistry.isNewer(t0.addingTimeInterval(-86400), than: installed))
    }

    /// Une date manquante d'un côté ou de l'autre ne conclut à rien : mieux
    /// vaut ne rien annoncer qu'annoncer une mise à jour qui n'existe pas.
    @Test func aMissingDateAnnouncesNothing() {
        #expect(!InstalledTranslationRegistry.isNewer(nil, than: t0))
        #expect(!InstalledTranslationRegistry.isNewer(t0, than: nil))
        #expect(!InstalledTranslationRegistry.isNewer(nil, than: nil))
    }

    /// Le registre traverse un enregistrement : c'est une trace qu'on relira
    /// des mois plus tard, quand la traduction devra être désinstallée.
    @Test func theRegistrySurvivesAnEncodeDecodeRoundTrip() throws {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(replaced: ["i18n/fr.json": "ailleurs"]))
        let data = try JSONEncoder().encode(registry)
        #expect(try JSONDecoder().decode(InstalledTranslationRegistry.self, from: data) == registry)
    }

    /// La clé est le nom **logique** du dossier : mettre le mod en pause le
    /// préfixe d'un point sur le disque, mais la traduction reste la sienne.
    @Test func aPausedHostKeepsItsTranslation() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(host: "Parchment"))
        #expect(registry.translation(forHost: "Parchment") != nil)
        #expect(registry.translation(forHost: ".Parchment") == nil)
    }
}
