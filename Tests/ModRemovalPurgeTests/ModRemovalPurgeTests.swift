import Testing
import Foundation
@testable import StarHubTHCore

/// X55 — ce qu'il reste d'un mod après sa suppression.
///
/// `deleteMod` purgeait les favoris, l'historique d'erreurs, la référence de
/// traduction et la couverture FR, mais laissait quatre magasins indexés sur le
/// même nom de dossier — le drapeau « sa config suit le profil », l'horodatage
/// d'activation, l'identifiant Nexus saisi à la main et la catégorie choisie —
/// plus la présence du mod dans « Je l'ai » de la vitrine, indexée sur
/// l'identifiant Nexus.
///
/// Politique tranchée le 2026-09-04 : **on efface tout**. Ce qu'on supprime
/// disparaît, et une réinstallation repart d'une page blanche.
struct ModRemovalPurgeTests {

    @Test func theModsOwnKeyGoes() {
        #expect(ModRemovalPurge.keysToRemove(from: ["A", "B"], removing: "A") == ["A"])
    }

    @Test func theComponentsOfADeletedPackGoWithIt() {
        // Supprimer un pack efface son dossier **entier** : ses composants
        // n'existent plus non plus, et leur `folderName` est le chemin relatif
        // sous le pack.
        let keys = ["[CP] Pack", "[CP] Pack/Composant", "[CP] Pack/Autre"]
        #expect(ModRemovalPurge.keysToRemove(from: keys, removing: "[CP] Pack")
                == Set(keys))
    }

    @Test func aNeighbourWhoseNameMerelyStartsTheSameStays() {
        // Le voisin qui ne doit **pas** partir : la règle porte sur un
        // préfixe suivi d'une barre, jamais sur un préfixe nu — sans quoi
        // supprimer `Pack` emporterait `PackDeLuxe`, qui est un autre mod.
        let keys = ["Pack", "PackDeLuxe", "Pack2", "Pack/Composant"]
        #expect(ModRemovalPurge.keysToRemove(from: keys, removing: "Pack")
                == ["Pack", "Pack/Composant"])
    }

    @Test func deletingAComponentLeavesItsPackAlone() {
        // L'inverse : on peut supprimer un composant seul, et le pack reste.
        let keys = ["[CP] Pack", "[CP] Pack/Composant", "[CP] Pack/Autre"]
        #expect(ModRemovalPurge.keysToRemove(from: keys, removing: "[CP] Pack/Composant")
                == ["[CP] Pack/Composant"])
    }

    @Test func nothingMatchesNothing() {
        #expect(ModRemovalPurge.keysToRemove(from: ["A", "B"], removing: "C").isEmpty)
        #expect(ModRemovalPurge.keysToRemove(from: [], removing: "A").isEmpty)
    }

    @Test func theKeyIsLogical_soADotPrefixedNameNeverMatches() {
        // `folderName` est **logique** : le point d'un mod en pause vit sur
        // `physicalFolderName`, et aucun magasin n'est indexé dessus. Une clé
        // pointée serait donc une anomalie — on ne la ramasse pas au passage,
        // sinon on effacerait l'entrée d'un mod homonyme encore installé
        // (`X` actif et `.X` en pause sont deux mods différents, cas réel).
        #expect(ModRemovalPurge.keysToRemove(from: [".Pack", "Pack"], removing: "Pack")
                == ["Pack"])
    }

    @Test func aDictionaryIsPurgedInPlace() {
        var stamps = ["A": Date(timeIntervalSince1970: 1),
                      "A/Composant": Date(timeIntervalSince1970: 2),
                      "B": Date(timeIntervalSince1970: 3)]
        let changed = ModRemovalPurge.purge(&stamps, removing: "A")
        #expect(changed)
        #expect(Set(stamps.keys) == ["B"])
    }

    @Test func purgingWhatIsNotThereChangesNothingAndSaysSo() {
        // Le retour dit s'il faut réécrire le magasin sur disque : réécrire
        // pour rien, c'est une écriture de UserDefaults par suppression sans
        // objet.
        var stamps = ["B": Date(timeIntervalSince1970: 3)]
        #expect(ModRemovalPurge.purge(&stamps, removing: "A") == false)
        #expect(stamps.count == 1)
    }

    @Test func aSetIsPurgedTheSameWay() {
        var flags: Set<String> = ["A", "A/Composant", "B"]
        #expect(ModRemovalPurge.purge(&flags, removing: "A"))
        #expect(flags == ["B"])
    }
}
