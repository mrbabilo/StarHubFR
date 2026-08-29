import Testing
import Foundation
@testable import StarHubTHCore

struct ModConflictVerdictsTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034)

    /// **Une paire n'a pas d'ordre.** « A avec B » et « B avec A » sont le même
    /// signalement ; sans cela l'utilisateur en créerait deux sans le savoir.
    @Test func aPairIsUnordered() throws {
        var store = ModConflictVerdicts()
        store.declare(ModConflictPair("SVE", "[CP] Make Gunther Real"), note: "", at: t0)
        #expect(store.verdict(for: ModConflictPair("[CP] Make Gunther Real", "SVE")) != nil)
    }

    /// **Un seul verdict par paire, le dernier gagne.** Déclarer une paire
    /// écartée la remet au rapport.
    @Test func aNewVerdictReplacesThePrevious() throws {
        var store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        store.dismiss(pair, note: "faux positif", at: t0)
        store.declare(pair, note: "vérifié en jeu", at: t0.addingTimeInterval(60))
        #expect(store.verdict(for: pair)?.isDeclared == true)
        #expect(store.verdict(for: pair)?.note == "vérifié en jeu")
    }

    /// La clé est le `folderName` **logique** : un mod mis en pause vit dans un
    /// dossier préfixé d'un point, et son verdict doit le suivre.
    @Test func aPausedModKeepsItsVerdict() throws {
        var store = ModConflictVerdicts()
        store.declare(ModConflictPair("Swim", "Parchment"), note: "", at: t0)
        #expect(store.verdict(for: ModConflictPair("Swim", "Parchment")) != nil)
        #expect(store.verdict(for: ModConflictPair(".Swim", "Parchment")) == nil)
    }

    /// **Un verdict orphelin se dit, il ne se jette pas.** Un mod désinstallé
    /// laisse un signalement qui ne désigne plus rien ; l'effacer en silence
    /// perdrait ce que l'utilisateur avait appris.
    @Test func verdictsPointingAtAbsentModsAreReported() throws {
        var store = ModConflictVerdicts()
        store.declare(ModConflictPair("A", "Disparu"), note: "", at: t0)
        store.declare(ModConflictPair("A", "B"), note: "", at: t0)
        let orphans = store.orphans(among: ["A", "B"])
        #expect(orphans.count == 1)
        #expect(orphans.first?.contains("Disparu") == true)
    }

    @Test func theStoreSurvivesAnEncodeDecodeRoundTrip() throws {
        var store = ModConflictVerdicts()
        store.declare(ModConflictPair("A", "B"), note: "cassé en jeu", at: t0)
        store.dismiss(ModConflictPair("C", "D"), note: "", at: t0)
        let data = try JSONEncoder().encode(store)
        let back = try JSONDecoder().decode(ModConflictVerdicts.self, from: data)
        #expect(back == store)
    }

    /// **L'ordre d'encodage doit être total.** Trois paires partageant leur
    /// premier nom : trier sur lui seul laissait leur ordre relatif au hasard du
    /// hachage, et le fichier JSON changerait à chaque sauvegarde sans qu'aucune
    /// donnée n'ait bougé.
    @Test func theEncodedOrderIsStableAcrossPairsSharingTheirFirstName() throws {
        var store = ModConflictVerdicts()
        for other in ["D", "B", "C"] {
            store.declare(ModConflictPair("A", other), note: "", at: t0)
        }
        #expect(store.declared.map(\.second) == ["B", "C", "D"])
    }
}
