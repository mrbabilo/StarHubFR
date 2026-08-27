import Foundation
import Testing
@testable import StarHubTHCore

/// B2-T4 : le bouton « Copier la commande » de la feuille d'installation ne
/// doit apparaître que pour l'erreur qui conseille une commande — l'outil RAR
/// manquant. La commande copiée doit rester celle que le message localisé
/// (`mod_install_rar_tool_missing`) et l'accueil (`home_tool_unar_*`)
/// recommandent déjà : `unar`, pas `unrar`.
@Suite struct CopyableCommandTests {

    @Test("L'outil RAR manquant porte la commande Homebrew à copier")
    func rarToolMissingCarriesCommand() {
        #expect(InstallError.rarToolMissing.copyableCommand == "brew install unar")
    }

    @Test("Aucune autre erreur d'installation ne porte de commande")
    func otherErrorsCarryNothing() {
        #expect(InstallError.extractionFailed("").copyableCommand == nil)
        #expect(InstallError.unsafeContent.copyableCommand == nil)
        #expect(InstallError.gameDirEmpty.copyableCommand == nil)
        #expect(InstallError.backupFailed("x").copyableCommand == nil)
        #expect(InstallError.installFailed("x").copyableCommand == nil)
    }
}
