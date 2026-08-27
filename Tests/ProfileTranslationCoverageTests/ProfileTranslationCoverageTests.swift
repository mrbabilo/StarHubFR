import Foundation
import Testing
@testable import StarHubTHCore

private func makeMod(_ uniqueId: String, name: String,
                     folderName: String? = nil) -> ModItem {
    ModItem(uniqueId: uniqueId,
            name: name,
            folderName: folderName ?? name,
            version: "1.0.0",
            author: "Auteur",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            isEnabled: true,
            dependencies: [])
}

private func coverage(total: Int, translated: Int) -> TranslationCoverage.Coverage {
    TranslationCoverage.Coverage(total: total, translated: translated,
                                 missing: [], empty: [], orphan: [],
                                 identicalToSource: [])
}

@Suite struct ProfileTranslationCoverageTests {

    // MARK: - L'agrégat

    /// L'agrégation se fait sur les **clés**, jamais sur une moyenne des
    /// pourcentages : un mod de 10 clés ne pèse pas autant qu'un mod de 1 000.
    @Test func keysAreSummedNotPercentagesAveraged() {
        let profile = ModProfile(name: "P", enabledModIds: ["a", "b"])
        let mods = [makeMod("a", name: "Petit"), makeMod("b", name: "Gros")]

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: mods,
            coverageByUniqueId: ["a": coverage(total: 10, translated: 10),
                                 "b": coverage(total: 1000, translated: 0)])

        // Une moyenne des pourcentages aurait annoncé 50 %.
        #expect(summary.totalKeys == 1010)
        #expect(summary.translatedKeys == 10)
        #expect(summary.displayPercent == 1)
        #expect(summary.translatableCount == 2)
        #expect(summary.fullyTranslatedCount == 1)
    }

    /// Un mod que le profil réclame mais qui n'est plus installé n'est pas
    /// mesurable : la section « mods manquants » le nomme déjà, et le compter
    /// à 0 % écraserait le pourcentage.
    @Test func aMissingModIsNotCountedAsUntranslated() {
        let profile = ModProfile(name: "P", enabledModIds: ["a", "disparu"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [makeMod("a", name: "A")],
            coverageByUniqueId: ["a": coverage(total: 100, translated: 50),
                                 "disparu": coverage(total: 900, translated: 0)])

        #expect(summary.translatableCount == 1)
        #expect(summary.totalKeys == 100)
        #expect(summary.pending.map(\.uniqueId) == ["a"])
    }

    /// Un mod sans `default.json` — une retexture, un pack de cartes — n'a
    /// jamais eu de français à perdre : il ne compte nulle part.
    @Test func aModWithNothingToTranslateIsIgnored() {
        let profile = ModProfile(name: "P", enabledModIds: ["a", "texture"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile,
            installedMods: [makeMod("a", name: "A"), makeMod("texture", name: "Texture")],
            coverageByUniqueId: ["a": coverage(total: 4, translated: 4)])

        #expect(summary.translatableCount == 1)
        #expect(summary.fullyTranslatedCount == 1)
        #expect(summary.pending.isEmpty)
        #expect(summary.displayPercent == 100)
    }

    /// Un profil sans aucun mod traduisible ne dit rien : la pastille reste
    /// absente plutôt que d'annoncer « 0 % », qui ferait croire à du travail.
    @Test func aProfileWithoutTranslatableModsIsEmpty() {
        let summary = ProfileTranslationCoverage.summarize(
            profile: ModProfile(name: "P", enabledModIds: ["texture"]),
            installedMods: [makeMod("texture", name: "Texture")],
            coverageByUniqueId: [:])

        #expect(summary.isEmpty)
        #expect(summary.displayPercent == 0)
    }

    /// La casse d'un `UniqueID` ne doit rien changer : SMAPI l'ignore, et un
    /// manifeste réédité avec une majuscule différente ferait autrement
    /// disparaître le mod du calcul.
    @Test func uniqueIdMatchingIgnoresCase() {
        let profile = ModProfile(name: "P", enabledModIds: ["Auteur.MonMod"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile,
            installedMods: [makeMod("auteur.monmod", name: "Mon Mod")],
            coverageByUniqueId: ["auteur.monmod": coverage(total: 10, translated: 3)])

        #expect(summary.translatableCount == 1)
        #expect(summary.pending.first?.name == "Mon Mod")
    }

    /// Un profil peut nommer deux fois le même identifiant (import de favoris
    /// puis ajout manuel) : le compter deux fois doublerait ses clés.
    @Test func aDuplicateEntryIsCountedOnce() {
        let profile = ModProfile(name: "P", enabledModIds: ["a", "A"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [makeMod("a", name: "A")],
            coverageByUniqueId: ["a": coverage(total: 10, translated: 5)])

        #expect(summary.translatableCount == 1)
        #expect(summary.totalKeys == 10)
    }

    // MARK: - La liste

    /// Le plus gros reste d'abord : c'est ce mod qui change le plus le
    /// pourcentage du profil. Mesuré sur son profil « OK » : `Friendable
    /// Mr.Qi` (3 394 clés) devance `East Scarp: NPCs` (3 072 manquantes).
    @Test func pendingModsAreSortedByRemainingKeys() {
        let profile = ModProfile(name: "P", enabledModIds: ["a", "b", "c"])
        let mods = [makeMod("a", name: "A"), makeMod("b", name: "B"), makeMod("c", name: "C")]

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: mods,
            coverageByUniqueId: ["a": coverage(total: 100, translated: 90),
                                 "b": coverage(total: 4000, translated: 1000),
                                 "c": coverage(total: 50, translated: 0)])

        #expect(summary.pending.map(\.uniqueId) == ["b", "c", "a"])
        #expect(summary.pending.first?.missingCount == 3000)
    }

    /// À reste égal, l'alphabet — pour que deux affichages successifs ne se
    /// réordonnent pas sous les yeux de l'utilisateur.
    @Test func tiesAreBrokenAlphabetically() {
        let profile = ModProfile(name: "P", enabledModIds: ["z", "a"])
        let mods = [makeMod("z", name: "Zèbre"), makeMod("a", name: "Abeille")]

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: mods,
            coverageByUniqueId: ["z": coverage(total: 10, translated: 0),
                                 "a": coverage(total: 10, translated: 0)])

        #expect(summary.pending.map(\.name) == ["Abeille", "Zèbre"])
    }

    /// Un mod entièrement traduit ne figure pas dans la liste : il n'y a rien
    /// à y faire.
    @Test func fullyTranslatedModsAreNotListed() {
        let profile = ModProfile(name: "P", enabledModIds: ["a"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [makeMod("a", name: "A")],
            coverageByUniqueId: ["a": coverage(total: 7, translated: 7)])

        #expect(summary.pending.isEmpty)
        #expect(summary.fullyTranslatedCount == 1)
    }

    /// La rangée porte le dossier logique : c'est la seule clé qui ouvre la
    /// fiche du mod, et pour un composant de pack ce n'est pas son nom.
    @Test func aPackComponentKeepsItsFolderPath() {
        let profile = ModProfile(name: "P", enabledModIds: ["comp"])
        let mod = makeMod("comp", name: "Composant", folderName: "MonPack/Composant")

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [mod],
            coverageByUniqueId: ["comp": coverage(total: 10, translated: 1)])

        #expect(summary.pending.first?.folderName == "MonPack/Composant")
    }

    // MARK: - Les arrondis

    /// « 100 » n'est rendu que si tout est traduit : annoncer un travail
    /// terminé alors qu'il manque une clé sur mille est le seul arrondi que ce
    /// chiffre ne peut pas se permettre.
    @Test func almostCompleteNeverReadsAsHundred() {
        let profile = ModProfile(name: "P", enabledModIds: ["a"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [makeMod("a", name: "A")],
            coverageByUniqueId: ["a": coverage(total: 1000, translated: 999)])

        #expect(summary.displayPercent == 99)
        #expect(summary.pending.first?.displayPercent == 99)
    }

    /// Et un début de traduction n'est jamais ramené à « 0 », qui le ferait
    /// passer pour rien du tout.
    @Test func aStartedTranslationNeverReadsAsZero() {
        let profile = ModProfile(name: "P", enabledModIds: ["a"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [makeMod("a", name: "A")],
            coverageByUniqueId: ["a": coverage(total: 1000, translated: 1)])

        #expect(summary.displayPercent == 1)
        #expect(summary.pending.first?.displayPercent == 1)
    }

    /// Zéro clé traduite reste zéro : c'est le cas des 8, 28 et 15 mods sans
    /// aucun français relevés sur ses trois profils.
    @Test func anUntouchedModReadsAsZero() {
        let profile = ModProfile(name: "P", enabledModIds: ["a"])

        let summary = ProfileTranslationCoverage.summarize(
            profile: profile, installedMods: [makeMod("a", name: "A")],
            coverageByUniqueId: ["a": coverage(total: 292, translated: 0)])

        #expect(summary.displayPercent == 0)
        #expect(summary.pending.first?.displayPercent == 0)
        #expect(summary.pending.first?.missingCount == 292)
    }
}
