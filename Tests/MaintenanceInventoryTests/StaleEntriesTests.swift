import Testing
import Foundation
@testable import StarHubTHCore

/// Les deux familles sans poids : 340 dossiers de session que l'index ne
/// référence plus (336 à zéro octet) et 35 clés de préférences qui nomment des
/// dossiers disparus. Mesuré le 2026-09-04.
struct StaleEntriesTests {

    @Test func aSessionFolderTheIndexIgnoresIsAnOrphan() {
        let onDisk: Set<String> = ["2026-07-26_145243_A_install_backup",
                                   "2026-07-26_145318_B_install_backup"]
        let referenced: Set<String> = ["2026-07-26_145243_A_install_backup"]
        #expect(MaintenanceInventory.orphanSessions(onDisk: onDisk, referenced: referenced,
                                                    indexWasReadable: true)
                == ["2026-07-26_145318_B_install_backup"])
    }

    @Test func anIndexEntryWithoutItsFolderIsNotAnOrphanOfThisKind() {
        // L'inverse n'est pas un orphelin de dossier : c'est une entrée d'index
        // qui pointe dans le vide, et rien à supprimer sur le disque.
        #expect(MaintenanceInventory.orphanSessions(onDisk: [], referenced: ["X"],
                                                    indexWasReadable: true).isEmpty)
    }

    @Test func aKeyNamingAnInstalledModSurvives() {
        #expect(MaintenanceInventory.stalePreferenceKeys(["Automate", "Disparu"],
                                                         installedFolders: ["Automate"])
                == ["Disparu"])
    }

    @Test func aPackComponentKeySurvivesWithItsPack() {
        // `folderName` d'un composant est le chemin relatif sous le pack. Le pack
        // installé garde ses composants.
        let keys = ["[CP] Pack", "[CP] Pack/Composant"]
        #expect(MaintenanceInventory.stalePreferenceKeys(
            keys, installedFolders: ["[CP] Pack", "[CP] Pack/Composant"]).isEmpty)
    }

    @Test func theNeighbourWhoseNameMerelyStartsTheSameIsJudgedOnItsOwn() {
        // Le voisin qui ne doit **pas** partir avec l'autre : `PackDeLuxe` est un
        // mod distinct de `Pack`, et son sort ne dépend que de sa propre présence.
        let keys = ["Pack", "PackDeLuxe"]
        #expect(MaintenanceInventory.stalePreferenceKeys(keys, installedFolders: ["PackDeLuxe"])
                == ["Pack"])
    }

    @Test func anEmptyKeyIsNeverReported() {
        #expect(MaintenanceInventory.stalePreferenceKeys(["", "A"],
                                                         installedFolders: ["A"]).isEmpty)
    }
}

/// X70 — **un parc qu'on ne voit pas n'est pas un parc vide.**
///
/// `stalePreferenceKeys` juge chaque clé sur son absence de `installedFolders`.
/// Quand ce lot est vide — dossier de jeu introuvable ou déplacé, disque
/// externe débranché, balayage pas encore terminé quand l'écran s'ouvre —
/// **toutes** les clés paraissent mortes, et le bouton « nettoyer » les efface.
///
/// Sur le parc de référence, mesuré le 2026-09-05 : **616 entrées** partiraient
/// — 437 dates d'activation, 169 identifiants Nexus saisis à la main, 10 mods
/// à configuration suivie par profil. Les identifiants Nexus, en particulier,
/// ne se retrouvent qu'à la main, un par un.
///
/// C'est la règle que l'écran s'était déjà donnée pour les dossiers de session
/// orphelins : « une suppression ne se décide pas sur une absence constatée
/// toute seule ». Elle vaut ici pour la même raison.
/// X76 — **un index qu'on n'a pas lu ne rend pas orphelins les
/// dossiers qu'il référence.** `loadBackups` rend `[]` aussi bien au premier
/// lancement que sur un index corrompu ; si l'inventaire calcule alors
/// `onDisk − referenced`, chaque session réelle passe pour un dossier que
/// l'index ignore — et le bouton « nettoyer » les met toutes à la corbeille.
/// Même règle que X70/X71, appliquée au troisième lot de l'écran.
@Suite("Entretien — un index illisible n'autorise aucun verdict d'orphelin")
struct OrphansNeedAReadableIndexTests {

    @Test func anUnreadableIndexDeclaresNoOrphans() {
        let onDisk: Set<String> = ["2026-08-06_171624_A_install_backup",
                                   "2026-08-06_172648_B_install_backup"]
        #expect(MaintenanceInventory.orphanSessions(onDisk: onDisk,
                                                    referenced: [],
                                                    indexWasReadable: false).isEmpty,
                "des sessions présentes ne sont pas des orphelins parce que l'index est illisible")
    }

    /// Le cas voisin qui ne doit **pas** changer : index lu, orphelins
    /// réels — les 340 dossiers que l'index ignore volontairement (X25).
    @Test func aReadableIndexStillJudgesItsOrphans() {
        let onDisk: Set<String> = ["A_install_backup", "B_install_backup"]
        #expect(MaintenanceInventory.orphanSessions(onDisk: onDisk,
                                                    referenced: ["A_install_backup"],
                                                    indexWasReadable: true)
                == ["B_install_backup"])
    }
}

@Suite("Entretien — un parc illisible n'autorise aucune purge")
struct StaleKeysNeedAKnownParcTests {

    @Test func anEmptyParcDeclaresNothingStale() {
        let keys = ["Automate", "Disparu", "Pack/Composant"]
        #expect(MaintenanceInventory.stalePreferenceKeys(keys, installedFolders: [])
                    .isEmpty,
                "un parc vide fait passer toutes les clés pour mortes")
    }

    /// Le cas voisin qui ne doit **pas** changer : dès qu'un seul mod est vu,
    /// le parc est lisible et le jugement reprend normalement.
    @Test func aSingleKnownModIsEnoughToJudgeTheOthers() {
        #expect(MaintenanceInventory.stalePreferenceKeys(["Automate", "Disparu"],
                                                         installedFolders: ["Automate"])
                == ["Disparu"])
    }
}
