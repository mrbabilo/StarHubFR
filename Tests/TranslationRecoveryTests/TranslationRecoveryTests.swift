import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct TranslationRecoveryDiffTests {

    /// Le cas qui motive tout : une mise à jour a rendu le mod à sa version
    /// anglaise, l'utilisateur en a retraduit une partie, et la sauvegarde
    /// porte encore le reste. Ces clés-là sont récupérables **sans toucher**
    /// à ce qui a été traduit depuis.
    @Test func aKeyOnlyInTheBackupIsRecoverable() {
        let diff = TranslationRecoveryDiff.compare(backup: ["a": "Bonjour", "b": "Merci"],
                                                   installed: ["b": "Merci beaucoup"])

        let recoverable = diff.filter { $0.kind == .onlyInBackup }
        #expect(recoverable.map(\.key) == ["a"])
        #expect(recoverable.first?.backupValue == "Bonjour")
        #expect(recoverable.first?.installedValue == nil)
    }

    /// Ce qui a été traduit depuis n'est **jamais** proposé au remplacement :
    /// la valeur de la sauvegarde est plus ancienne, pas meilleure. La ligne
    /// est montrée, mais comme une divergence.
    @Test func aKeyTranslatedSinceIsShownAsDivergingNotRecoverable() {
        let diff = TranslationRecoveryDiff.compare(backup: ["b": "Merci"],
                                                   installed: ["b": "Merci beaucoup"])

        #expect(diff.map(\.kind) == [.valueDiffers])
        #expect(diff.first?.backupValue == "Merci")
        #expect(diff.first?.installedValue == "Merci beaucoup")
    }

    /// Une clé que seul l'installé porte : le mod a grandi depuis la
    /// sauvegarde, ou l'utilisateur l'a traduite. Rien à récupérer, mais elle
    /// explique l'écart de comptage.
    @Test func aKeyOnlyInTheInstalledFileIsReported() {
        let diff = TranslationRecoveryDiff.compare(backup: [:], installed: ["c": "Nouveau"])

        #expect(diff.map(\.kind) == [.onlyInInstalled])
        #expect(diff.first?.installedValue == "Nouveau")
    }

    /// Une clé identique des deux côtés n'est pas un écart : elle n'a rien à
    /// faire dans un diff.
    @Test func anIdenticalKeyIsNotListed() {
        let diff = TranslationRecoveryDiff.compare(backup: ["a": "Bonjour"],
                                                   installed: ["a": "Bonjour"])

        #expect(diff.isEmpty)
    }

    /// SMAPI compare ses clés sans égard à la casse : `Item.Name` et
    /// `item.name` sont **la même clé**, et les confondre ferait réinjecter un
    /// doublon invisible en jeu.
    @Test func keysThatDifferOnlyByCaseAreTheSameKey() {
        let diff = TranslationRecoveryDiff.compare(backup: ["Item.Name": "Épée"],
                                                   installed: ["item.name": "Épée"])

        #expect(diff.isEmpty)
    }

    /// Ce qui est récupérable vient en tête : c'est la seule famille sur
    /// laquelle l'utilisateur a un geste à faire.
    @Test func recoverableKeysComeFirst() {
        let diff = TranslationRecoveryDiff.compare(
            backup: ["z": "sauvegardée", "d": "diverge"],
            installed: ["d": "différente", "a": "ajoutée"])

        #expect(diff.map(\.kind) == [.onlyInBackup, .valueDiffers, .onlyInInstalled])
    }

    /// À famille égale, l'ordre des clés est celui du fichier de sauvegarde
    /// pour ce qu'il porte, alphabétique sinon : deux affichages successifs ne
    /// se réordonnent pas.
    @Test func theOrderIsStableWithinAFamily() {
        let diff = TranslationRecoveryDiff.compare(backup: ["z": "1", "a": "2", "m": "3"],
                                                   installed: [:])

        #expect(diff.map(\.key) == ["a", "m", "z"])
    }

    /// Une valeur vide dans la sauvegarde n'est pas une traduction : la
    /// proposer effacerait la clé sans rien apporter.
    @Test func anEmptyBackupValueIsNotRecoverable() {
        let diff = TranslationRecoveryDiff.compare(backup: ["a": "   "], installed: [:])

        #expect(diff.isEmpty)
    }

    /// Les clés à réinjecter, prêtes pour `TranslationDocument.apply` : la
    /// **clé de la sauvegarde**, telle qu'elle y est écrite.
    @Test func theEditsToApplyCarryTheBackupsOwnSpelling() {
        let diff = TranslationRecoveryDiff.compare(backup: ["Item.Name": "Épée", "b": "Merci"],
                                                   installed: [:])

        let edits = TranslationRecoveryDiff.edits(for: diff.filter { $0.key == "Item.Name" })

        #expect(edits == ["Item.Name": "Épée"])
    }

    /// On ne réinjecte que ce qui est récupérable, même si l'appelant passe
    /// une ligne d'une autre famille : c'est la dernière barrière avant
    /// d'écrire dans le fichier du traducteur.
    @Test func edritsNeverIncludeADivergingKey() {
        let diff = TranslationRecoveryDiff.compare(backup: ["b": "Merci"],
                                                   installed: ["b": "Merci beaucoup"])

        #expect(TranslationRecoveryDiff.edits(for: diff).isEmpty)
    }
}
