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
        #expect(MaintenanceInventory.orphanSessions(onDisk: onDisk, referenced: referenced)
                == ["2026-07-26_145318_B_install_backup"])
    }

    @Test func anIndexEntryWithoutItsFolderIsNotAnOrphanOfThisKind() {
        // L'inverse n'est pas un orphelin de dossier : c'est une entrée d'index
        // qui pointe dans le vide, et rien à supprimer sur le disque.
        #expect(MaintenanceInventory.orphanSessions(onDisk: [], referenced: ["X"]).isEmpty)
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
