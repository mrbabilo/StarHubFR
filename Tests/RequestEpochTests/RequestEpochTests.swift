import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct RequestEpochTests {

    /// Le cas ordinaire : une seule demande en vol, sa réponse est la bonne.
    @Test func theAnswerToTheOnlyPendingRequestIsAccepted() {
        var epoch = RequestEpoch()
        let token = epoch.open()
        #expect(epoch.isCurrent(token))
    }

    /// **Le cas de X49.** Deux recherches lancées coup sur coup : la réponse de
    /// la première ne doit plus rien écrire, même si elle arrive en dernier.
    @Test func theAnswerToASupersededRequestIsRefused() {
        var epoch = RequestEpoch()
        let first = epoch.open()
        let second = epoch.open()

        #expect(!epoch.isCurrent(first))
        #expect(epoch.isCurrent(second))
    }

    /// L'ordre d'arrivée ne change rien : c'est la demande qui décide, pas la
    /// réponse. La seconde reste recevable après que la première est revenue.
    @Test func theOrderOfArrivalDoesNotDecide() {
        var epoch = RequestEpoch()
        let first = epoch.open()
        let second = epoch.open()

        // La première revient d'abord, refusée…
        #expect(!epoch.isCurrent(first))
        // …et la seconde reste attendue.
        #expect(epoch.isCurrent(second))
    }

    /// Quitter l'écran périme ce qui est en vol : sans cela, une réponse
    /// arrivée une seconde trop tard ferait revenir des résultats que
    /// l'utilisateur venait de fermer.
    @Test func abandoningRefusesWhatIsStillInFlight() {
        var epoch = RequestEpoch()
        let token = epoch.open()
        epoch.abandonAll()

        #expect(!epoch.isCurrent(token))
    }

    /// Une pagination suit la demande en cours sans en ouvrir une : demander
    /// « la suite » ne doit pas invalider la recherche qu'elle prolonge.
    @Test func followingTheCurrentRequestDoesNotSupersedeIt() {
        var epoch = RequestEpoch()
        let search = epoch.open()
        let more = epoch.currentToken

        #expect(more == search)
        #expect(epoch.isCurrent(search))
    }

    /// Une réponse dont le jeton n'a jamais été distribué n'est jamais
    /// courante — un jeton par défaut ne doit pas ouvrir la porte.
    @Test func aTokenThatWasNeverHandedOutIsNeverCurrent() {
        var epoch = RequestEpoch()
        let stale = epoch.currentToken
        _ = epoch.open()

        #expect(!epoch.isCurrent(stale))
    }
}
