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

    /// **Un fichier qui répète une paire ne doit pas tuer l'app.** Notre
    /// encodeur ne peut pas produire ce fichier (il part d'un dictionnaire),
    /// mais une édition manuelle ou une fusion de fichiers le peut — et le
    /// contrat de `load` est « fichier illisible → magasin vide », pas un
    /// crash au lancement : `Dictionary(uniqueKeysWithValues:)` lève un
    /// fatal error qu'aucun `try?` n'attrape. En cas de doublon, le
    /// **dernier** verdict du fichier gagne, comme un verdict re-posé.
    @Test func aFileRepeatingAPairDecodesInsteadOfCrashing() throws {
        let json = """
        {"entries":[
          {"pair":{"first":"A","second":"B"},"verdict":{"isDeclared":true,"note":"ancien","decidedAt":0}},
          {"pair":{"first":"A","second":"B"},"verdict":{"isDeclared":false,"note":"révisé","decidedAt":99}}
        ]}
        """
        let store = try JSONDecoder().decode(ModConflictVerdicts.self, from: Data(json.utf8))
        let pair = ModConflictPair("A", "B")
        #expect(store.verdict(for: pair)?.isDeclared == false)
        #expect(store.verdict(for: pair)?.note == "révisé")
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

    // MARK: - activationConflict (tâche 9 : avertissement à l'activation)

    /// Le cas simple : une paire déclarée, l'autre membre déjà actif.
    @Test func aDeclaredPairWithTheOtherModActiveTriggers() throws {
        var store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        store.declare(pair, note: "", at: t0)
        let other = store.activationConflict(activating: ["A"], candidates: [pair], activeFolders: ["B"])
        #expect(other == "B")
    }

    /// Écartée, silence — pas seulement retirée du rapport.
    @Test func aDismissedPairNeverTriggers() throws {
        var store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        store.dismiss(pair, note: "faux positif", at: t0)
        let other = store.activationConflict(activating: ["A"], candidates: [pair], activeFolders: ["B"])
        #expect(other == nil)
    }

    /// L'autre membre n'est pas actif aujourd'hui : rien à interrompre.
    @Test func aPairWhereTheOtherModIsNotActiveDoesNotTrigger() throws {
        let store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        let other = store.activationConflict(activating: ["A"], candidates: [pair], activeFolders: [])
        #expect(other == nil)
    }

    /// Aucune paire ne cite le mod qu'on active.
    @Test func aPairNotInvolvingTheActivatingModDoesNotTrigger() throws {
        let store = ModConflictVerdicts()
        let pair = ModConflictPair("X", "Y")
        let other = store.activationConflict(activating: ["A"], candidates: [pair], activeFolders: ["X", "Y"])
        #expect(other == nil)
    }

    /// **Le cas pack.** `activating` porte l'en-tête et ses composants : un
    /// conflit du journal citant « SVE/Farm » (composant) doit déclencher
    /// même si on active « SVE » (l'en-tête). Sans l'ensemble, cette paire
    /// ne matcherait jamais.
    @Test func aJournalPairCitingAPackComponentTriggersWhenTheHeaderActivates() throws {
        let store = ModConflictVerdicts()
        let pair = ModConflictPair("SVE/Farm", "Autre Pack")
        let other = store.activationConflict(activating: ["SVE", "SVE/Farm"],
                                              candidates: [pair], activeFolders: ["Autre Pack"])
        #expect(other == "Autre Pack")
    }

    /// Les deux membres de la paire sont dans `activating` (deux composants
    /// du **même** pack qu'on active ensemble, ou un `withinOnePack` (X, X)) :
    /// aucun mod tiers n'est en cause, donc pas d'avertissement.
    @Test func aPairWhoseTwoMembersAreBothActivatingDoesNotTrigger() throws {
        let store = ModConflictVerdicts()
        let pair = ModConflictPair("SVE/Farm", "SVE/Town")
        let other = store.activationConflict(activating: ["SVE", "SVE/Farm", "SVE/Town"],
                                              candidates: [pair], activeFolders: ["SVE/Farm", "SVE/Town"])
        #expect(other == nil)
    }

    // MARK: - liveConflictCount (pastille « Alertes système », spec A5-T2)

    /// **Une paire déclarée, les deux côtés actifs aujourd'hui → 1.** La
    /// pastille ne se fonde que sur l'état actuel du parc, jamais sur celui
    /// qu'avait le journal : une paire dormante ne demande pas d'attention.
    @Test func aDeclaredPairWithBothSidesActiveCountsOne() throws {
        var store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        store.declare(pair, note: "", at: t0)
        let count = store.liveConflictCount(candidates: store.declared, activeFolders: ["A", "B"])
        #expect(count == 1)
    }

    /// **Une paire observée, jamais jugée, les deux côtés actifs → 1** : le
    /// journal a vu le conflit, l'utilisateur ne l'a pas écarté.
    @Test func anObservedPairWithBothSidesActiveCountsOne() throws {
        let store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        let count = store.liveConflictCount(candidates: [pair], activeFolders: ["A", "B"])
        #expect(count == 1)
    }

    /// **Déclarée et observée, la même paire ne compte qu'une fois** — les
    /// candidates fusionnent avant de compter.
    @Test func aPairBothDeclaredAndObservedCountsOnce() throws {
        var store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        store.declare(pair, note: "", at: t0)
        let count = store.liveConflictCount(candidates: [pair] + store.declared, activeFolders: ["A", "B"])
        #expect(count == 1)
    }

    /// **Écartée → 0**, même observée dans le journal : « écarter » doit
    /// obtenir le silence partout, pas seulement dans le rapport.
    @Test func aDismissedPairNeverCounts() throws {
        var store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        store.dismiss(pair, note: "faux positif", at: t0)
        let count = store.liveConflictCount(candidates: [pair], activeFolders: ["A", "B"])
        #expect(count == 0)
    }

    /// **Dormante → 0** : un côté en pause ou désinstallé (absent des actifs)
    /// ne réclame rien aujourd'hui — c'est aussi le cas d'un nom du journal
    /// non résolu à un dossier, qui ne matche jamais un actif.
    @Test func aDormantPairDoesNotCount() throws {
        let store = ModConflictVerdicts()
        let pair = ModConflictPair("A", "B")
        #expect(store.liveConflictCount(candidates: [pair], activeFolders: ["A"]) == 0)
        #expect(store.liveConflictCount(candidates: [pair], activeFolders: []) == 0)
    }

    /// **L'ordre du tableau est déterministe, quel que soit l'ordre des
    /// candidats** — pas seulement le compte. Le filtre interne passe par un
    /// `Set` (itération non ordonnée) ; sans `sortPairs` en sortie, l'ordre
    /// affiché varierait d'un lancement à l'autre pour les mêmes données.
    /// Candidats volontairement mélangés (pas alphabétiques), bruités d'une
    /// paire dormante (un côté absent des actifs) et d'une paire écartée —
    /// toutes deux doivent disparaître du résultat, pas seulement être mal
    /// classées. Le compte, lui, doit rester exactement la taille de la
    /// liste : deux règles de filtrage finiraient par diverger, et la
    /// pastille annoncerait un nombre que l'écran ne montre pas — mais cette
    /// seule égalité resterait vraie même pour un tableau vide, donc elle ne
    /// remplace pas l'assertion de contenu ci-dessous.
    @Test func liveConflictsIsSortedFilteredAndDerivesTheCount() {
        var store = ModConflictVerdicts()
        let pairAB = ModConflictPair("A", "B")
        let pairCD = ModConflictPair("D", "C")
        let pairEF = ModConflictPair("F", "E")
        let pairGH = ModConflictPair("H", "G")
        let dormant = ModConflictPair("K", "L")
        let dismissed = ModConflictPair("M", "N")
        store.dismiss(dismissed, note: "faux positif", at: t0)
        let candidates = [pairGH, dismissed, pairAB, dormant, pairEF, pairCD]
        let active: Set<String> = ["A", "B", "C", "D", "E", "F", "G", "H", "M", "N"]
        let result = store.liveConflicts(candidates: candidates, activeFolders: active)
        #expect(result == [pairAB, pairCD, pairEF, pairGH])
        #expect(result.count == store.liveConflictCount(candidates: candidates, activeFolders: active))
    }
}
