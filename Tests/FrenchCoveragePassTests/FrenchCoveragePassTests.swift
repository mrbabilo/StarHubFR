import Testing
import Foundation
@testable import StarHubTHCore

/// La passe de couverture coûte ~13 s de lecture disque sur le parc de
/// référence, et `mods` est republié à chaque mise en pause, chaque
/// rafraîchissement, chaque activation de profil. Ce qui décide **qui** mesurer
/// et **comment** un lot entre dans l'état n'avait aucun test.
struct FrenchCoveragePassTests {

    private func mod(_ name: String, languages: [String] = ["en", "fr"],
                     enabled: Bool = true) -> ModItem {
        var m = ModItem(uniqueId: "id.\(name)", name: name, folderName: name, version: "1.0",
                        author: "", description: "", nexusUrl: "", nexusModId: "",
                        isEnabled: true, dependencies: [], children: nil,
                        languages: languages)
        m.isEnabled = enabled
        return m
    }

    private func coverage(_ translated: Int, of total: Int) -> TranslationCoverage.Coverage {
        .init(total: total, translated: translated, missing: [], empty: [],
              orphan: [], identicalToSource: [])
    }

    // MARK: - Choix du lot

    @Test func onlyModsShippingFrenchAreMeasured() {
        // C'est ce qui rend la passe abordable — et pourquoi la détection du
        // français devait être juste d'abord.
        let targets = FrenchCoveragePass.targets(
            in: [mod("Traduit"), mod("Anglais seul", languages: ["en"]),
                 mod("Sans i18n", languages: [])],
            known: [])
        #expect(targets.map(\.key) == ["Traduit"])
    }

    @Test func anAlreadyMeasuredModIsNotMeasuredAgain() {
        // Sans cette règle, les 13 s repartent à chaque republication de `mods`.
        let targets = FrenchCoveragePass.targets(in: [mod("Automate"), mod("Autre")],
                                                 known: ["Automate"])
        #expect(targets.map(\.key) == ["Autre"])
    }

    @Test func theListOrderIsPreserved() {
        // La liste se complète à mesure que le calcul avance : la mesurer dans
        // l'ordre affiché est ce qui fait apparaître les pastilles du haut
        // d'abord.
        let targets = FrenchCoveragePass.targets(in: [mod("Zeta"), mod("Alpha")], known: [])
        #expect(targets.map(\.key) == ["Zeta", "Alpha"])
    }

    @Test func aPausedModIsOpenedAtItsDottedFolderButKeyedOnItsLogicalName() {
        // Le piège que ce type existe pour rendre impossible : le dossier à lire
        // est `.Automate`, la clé de l'état publié reste `Automate`. Les
        // confondre ferait soit chercher dans le vide, soit reperdre la mesure à
        // chaque mise en pause.
        let targets = FrenchCoveragePass.targets(in: [mod("Automate", enabled: false)],
                                                 known: [])
        #expect(targets == [.init(key: "Automate", physicalFolder: ".Automate")])
    }

    @Test func nothingLeftToMeasureYieldsAnEmptyBatch() {
        #expect(FrenchCoveragePass.targets(in: [mod("Automate")], known: ["Automate"]).isEmpty)
    }

    // MARK: - Fusion d'un lot

    @Test func aBatchLandsInTheState() {
        let next = FrenchCoveragePass.merging(["Automate": coverage(40, of: 100)],
                                              stale: [], into: .init())
        #expect(next?.coverage["Automate"]?.displayPercent == 40)
    }

    @Test func anEmptyBatchChangesNothing() {
        // Pas de republication à vide : chaque merge redessine la liste.
        #expect(FrenchCoveragePass.merging([:], stale: [], into: .init()) == nil)
    }

    @Test func aBatchCarryingOnlyStalenessStillApplies() {
        let next = FrenchCoveragePass.merging([:], stale: ["Automate"], into: .init())
        #expect(next?.stale == ["Automate"])
    }

    @Test func aModOfTheBatchNoLongerFlaggedStopsBeingSuspect() {
        // Latent aujourd'hui — le balayage est incrémental, chaque mod n'est
        // mesuré qu'une fois. Nécessaire dès qu'une re-mesure ciblée existera,
        // et c'est précisément ce qu'un « nettoyage » retirerait sans rien
        // casser de visible.
        let before = FrenchCoveragePass.State(coverage: [:], stale: ["Automate"])
        let next = FrenchCoveragePass.merging(["Automate": coverage(100, of: 100)],
                                              stale: [], into: before)
        #expect(next?.stale.isEmpty == true)
    }

    @Test func aModOutsideTheBatchKeepsItsStaleness() {
        // Le voisin qui doit survivre : le retrait ne porte que sur ce que ce
        // lot a réexaminé. L'élargir viderait l'ensemble à chaque paquet de 25.
        let before = FrenchCoveragePass.State(coverage: [:], stale: ["Ailleurs"])
        let next = FrenchCoveragePass.merging(["Automate": coverage(100, of: 100)],
                                              stale: [], into: before)
        #expect(next?.stale == ["Ailleurs"])
    }

    @Test func aLaterMeasureOfTheSameModWins() {
        let before = FrenchCoveragePass.State(coverage: ["Automate": coverage(40, of: 100)])
        let next = FrenchCoveragePass.merging(["Automate": coverage(90, of: 100)],
                                              stale: [], into: before)
        #expect(next?.coverage["Automate"]?.displayPercent == 90)
    }

    // MARK: - F6-T1 : la course à l'annulation, rendue observable

    @Test func aBatchFromASupersededPassIsDropped() {
        // F6-T1. Le `cancel()` d'un recalcul n'interrompt pas une fusion déjà
        // engagée : un lot de ≤ 25 mesures de la génération précédente peut
        // atterrir après le recalcul suivant. Bénin tant que les fichiers ne
        // changent pas entre les deux ; réel le jour de la re-mesure ciblée.
        let before = FrenchCoveragePass.State(coverage: ["Automate": coverage(90, of: 100)])
        let next = FrenchCoveragePass.merging(["Automate": coverage(40, of: 100)],
                                              stale: [], into: before,
                                              generation: 0, currentGeneration: 1)
        #expect(next == nil)
    }

    @Test func aBatchFromTheCurrentPassApplies() {
        let next = FrenchCoveragePass.merging(["Automate": coverage(40, of: 100)],
                                              stale: [], into: .init(),
                                              generation: 1, currentGeneration: 1)
        #expect(next?.coverage["Automate"] != nil)
    }

    @Test func theDefaultGenerationIsAlwaysCurrent() {
        // L'appelant d'aujourd'hui ne compte pas les générations : sans
        // paramètre, la garde doit être inerte. La câbler serait corriger F6-T1
        // isolément, ce que la ROADMAP demande de ne pas faire.
        #expect(FrenchCoveragePass.merging(["Automate": coverage(40, of: 100)],
                                           stale: [], into: .init()) != nil)
    }

    // MARK: - Passe des profils : les mêmes gestes, d'autres règles

    private func profile(_ name: String, _ ids: [String]) -> ModProfile {
        ModProfile(name: name, enabledModIds: ids)
    }

    @Test func aModWithASourceButNoFrenchIsMeasuredForProfiles() {
        // La divergence assumée avec la passe de la liste : ce sont ces mods-là
        // qui font tout l'intérêt de l'écran des profils — 8, 28 et 15 sur les
        // trois profils de référence. La liste, elle, les écarte, parce qu'une
        // entrée y ferait surgir une pastille « 0 % ».
        let m = mod("Anglais seul", languages: ["en"])
        let targets = ProfileCoveragePass.targets(profiles: [profile("A", ["id.Anglais seul"])],
                                                  installed: [m], known: [])
        #expect(targets.map(\.id) == ["id.anglais seul"])
        // Et la même entrée est bien refusée par la passe de la liste.
        #expect(FrenchCoveragePass.targets(in: [m], known: []).isEmpty)
    }

    @Test func aModWithNoI18nAtAllIsSkippedEverywhere() {
        // Plus de la moitié du parc : les ouvrir serait le gros du coût pour rien.
        let m = mod("Sans i18n", languages: [])
        #expect(ProfileCoveragePass.targets(profiles: [profile("A", ["id.Sans i18n"])],
                                            installed: [m], known: []).isEmpty)
    }

    @Test func aModPresentInSeveralProfilesIsMeasuredOnce() {
        // La mesure porte sur le mod, pas sur son appartenance.
        let m = mod("Automate")
        let targets = ProfileCoveragePass.targets(
            profiles: [profile("A", ["id.Automate"]), profile("B", ["id.Automate"])],
            installed: [m], known: [])
        #expect(targets.count == 1)
    }

    @Test func aProfileNamingAnUninstalledModHasNothingToMeasure() {
        // Un profil garde ses `UniqueID` même quand le mod n'est plus là : il
        // n'y a rien à lire sur le disque.
        #expect(ProfileCoveragePass.targets(profiles: [profile("A", ["id.Parti"])],
                                            installed: [], known: []).isEmpty)
    }

    @Test func anAlreadyMeasuredModIsNotReopenedForProfiles() {
        // Sans ça, ouvrir la page des profils coûterait 15,7 s à chaque fois.
        #expect(ProfileCoveragePass.targets(profiles: [profile("A", ["id.Automate"])],
                                            installed: [mod("Automate")],
                                            known: ["id.automate"]).isEmpty)
    }

    @Test func theProfileKeyIsLowercasedOnBothSides() {
        // Les profils portent l'`UniqueID` tel que le manifest l'écrit ; la
        // comparaison se fait en minuscules des deux côtés, sinon un mod
        // n'est jamais retrouvé.
        let m = ModItem(uniqueId: "Pathoschild.Automate", name: "Automate",
                        folderName: "Automate", version: "1", author: "", description: "",
                        nexusUrl: "", nexusModId: "", isEnabled: true, dependencies: [],
                        children: nil, languages: ["en"])
        let targets = ProfileCoveragePass.targets(
            profiles: [profile("A", ["PATHOSCHILD.AUTOMATE"])], installed: [m], known: [])
        #expect(targets.map(\.id) == ["pathoschild.automate"])
    }

    @Test func aPausedProfileModIsOpenedAtItsDottedFolder() {
        let targets = ProfileCoveragePass.targets(
            profiles: [profile("A", ["id.Automate"])],
            installed: [mod("Automate", enabled: false)], known: [])
        #expect(targets == [.init(id: "id.automate", physicalFolder: ".Automate")])
    }

    @Test func anEmptyUniqueIdNamesNothing() {
        // 111 mods du parc n'ont **aucun identifiant** : leur dossier entre dans
        // l'index sous la clé vide. Sans le garde, un profil portant une entrée
        // vide — ou un mod sans manifest — ferait mesurer ce dossier-là comme
        // s'il avait été nommé.
        //
        // ⚠️ Ce test avait d'abord été écrit avec un parc où rien ne portait la
        // clé vide : il passait avec **comme sans** le garde, donc il ne
        // vérifiait rien. C'est le sabotage qui l'a montré.
        let anonymous = ModItem(uniqueId: "", name: "Sans manifest",
                                folderName: "Sans manifest", version: "", author: "",
                                description: "", nexusUrl: "", nexusModId: "",
                                isEnabled: true, dependencies: [], children: nil,
                                languages: ["en"])
        #expect(ProfileCoveragePass.targets(profiles: [profile("A", [""])],
                                            installed: [anonymous], known: []).isEmpty)
    }

    @Test func targetsFollowProfileOrder() {
        let targets = ProfileCoveragePass.targets(
            profiles: [profile("A", ["id.Zeta"]), profile("B", ["id.Alpha"])],
            installed: [mod("Alpha"), mod("Zeta")], known: [])
        #expect(targets.map(\.id) == ["id.zeta", "id.alpha"])
    }
}
