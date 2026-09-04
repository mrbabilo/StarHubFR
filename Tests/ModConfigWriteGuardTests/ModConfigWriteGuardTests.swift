import Testing
import Foundation
@testable import StarHubTHCore

/// C4-T6 — la règle qui décide si l'éditeur peut écrire `config.json`.
///
/// **Ce qu'elle protège.** Un mod C# réécrit sa propre config quand il veut :
/// UltraSmooth appelle `WriteConfig` depuis quatre sites de son `ModEntry`
/// (migration, bascule de profil, commandes), Modern Config Menu depuis cinq,
/// et la vue « raccourcis » de GMCM réécrit d'un coup **tous** les mods qui
/// déclarent une touche. Le fichier est donc volatile tant que le jeu tourne
/// — et l'éditeur lisait le sien à l'ouverture pour l'écraser en bloc à
/// l'enregistrement, sans jamais regarder s'il avait bougé entre-temps.
///
/// Le filet ne rattrape pas ce cas : `backUpCurrentConfig` ne garde **qu'une
/// sauvegarde par mod et par jour**, la première. Éditer à 10 h, laisser le
/// jeu réécrire à 14 h, éditer de nouveau à 15 h : la sauvegarde du jour est
/// celle d'avant 10 h, et l'état de 14 h n'existe plus nulle part.
struct ModConfigWriteGuardTests {

    @Test func writingOntoWhatWeLoadedIsFine() {
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}",
                                           onDisk: .content("{\"a\": 1}"),
                                           pending: "{\"a\": 2}") == .proceed)
    }

    @Test func aFileRewrittenSinceWeLoadedItStopsTheWrite() {
        // Le cas réel : le jeu tourne, le mod a réécrit sa config.
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}",
                                           onDisk: .content("{\"a\": 99}"),
                                           pending: "{\"a\": 2}") == .externallyChanged)
    }

    @Test func aRewriteThatLandedOnExactlyWhatWeWereGoingToWriteIsNotAConflict() {
        // Rien à perdre : le disque porte déjà, au caractère près, ce qu'on
        // allait écrire. Demander une confirmation ici serait une friction
        // pure — l'écriture est un non-événement.
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}",
                                           onDisk: .content("{\"a\": 2}"),
                                           pending: "{\"a\": 2}") == .proceed)
    }

    @Test func aReformattingCountsAsARewrite() {
        // Même JSON, autres octets : le mod **a** réécrit le fichier, et ce
        // qu'il a écrit peut porter des champs migrés. On avertit. Un faux
        // positif coûte une confirmation ; le manquer coûte le fichier.
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}",
                                           onDisk: .content("{\n  \"a\": 1\n}"),
                                           pending: "{\"a\": 2}") == .externallyChanged)
    }

    @Test func aFileWeCannotReReadIsNeverTakenForConsent() {
        // Le piège de X25 en miniature : là-bas, un index illisible rendait
        // un index **vide**, et tout le parc passait pour orphelin. Une
        // relecture qui échoue ne dit pas « rien n'a bougé » — elle ne dit
        // rien du tout, et on ne l'interprète pas.
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}",
                                           onDisk: .unreadable,
                                           pending: "{\"a\": 2}") == .unverifiable)
    }

    @Test func aConfigThatDidNotExistAndStillDoesNotIsFine() {
        // L'éditeur s'ouvre aussi sur un mod sans `config.json` : il montre
        // `{}` et le premier enregistrement crée le fichier.
        #expect(ModConfigWriteGuard.decide(loaded: nil,
                                           onDisk: .missing,
                                           pending: "{\"a\": 1}") == .proceed)
    }

    @Test func aConfigThatAppearedWhileWeWereEditingStopsTheWrite() {
        // Le mod vient d'écrire ses défauts — au premier lancement, ou après
        // une réinstallation. Les écraser en aveugle perdrait la migration.
        #expect(ModConfigWriteGuard.decide(loaded: nil,
                                           onDisk: .content("{\"a\": 42}"),
                                           pending: "{\"a\": 1}") == .externallyChanged)
    }

    @Test func aConfigThatVanishedWhileWeWereEditingIsNotAConflict() {
        // Le fichier a été supprimé (désinstallation, ménage). Le réécrire ne
        // détruit rien : il n'y a plus rien à détruire.
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}",
                                           onDisk: .missing,
                                           pending: "{\"a\": 2}") == .proceed)
    }

    @Test func onlyTheBytesCount_notTheirEncodingOfNewlines() {
        // CRLF contre LF, c'est une réécriture — et le piège maison veut
        // qu'on ne compare **jamais** deux textes en supposant `\n`.
        // `"a\r\nb"` ne fait que 3 `Character` en Swift : une comparaison
        // naïve par lignes les tiendrait pour identiques.
        #expect(ModConfigWriteGuard.decide(loaded: "{\"a\": 1}\n",
                                           onDisk: .content("{\"a\": 1}\r\n"),
                                           pending: "{\"a\": 2}") == .externallyChanged)
    }

    @Test func theDecisionIsPurelyAboutTheDisk_notAboutWhetherTheGameIsRunning() {
        // Le jeu qui tourne est un **avertissement**, pas une interdiction :
        // 379 des 462 mods à `config.json` du parc sont en pause, et éditer
        // la config d'un mod en pause pendant que le jeu tourne ne risque
        // rien. La règle ne connaît donc que le fichier.
        #expect(ModConfigWriteGuard.decide(loaded: "x", onDisk: .content("x"),
                                           pending: "y") == .proceed)
    }
}
