import Testing
import Foundation
@testable import StarHubTHCore

struct UpdateCheckPolicyTests {
    /// Le TTL d'A2-T4 : 12 h retenu au cadrage du 2026-08-31.
    private let ttl: TimeInterval = 12 * 3600
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func jamaisVérifié() {
        #expect(UpdateCheckPolicy.shouldAutoCheck(lastSuccess: nil, now: now, ttl: ttl))
    }

    @Test func frais() {
        let last = now.addingTimeInterval(-(11 * 3600))
        #expect(!UpdateCheckPolicy.shouldAutoCheck(lastSuccess: last, now: now, ttl: ttl))
    }

    @Test func périmé() {
        let limit = now.addingTimeInterval(-ttl)
        #expect(UpdateCheckPolicy.shouldAutoCheck(lastSuccess: limit, now: now, ttl: ttl))
        let older = now.addingTimeInterval(-(12 * 3600 + 60))
        #expect(UpdateCheckPolicy.shouldAutoCheck(lastSuccess: older, now: now, ttl: ttl))
    }

    // MARK: - après un choix de dossier (2026-09-17)

    /// Un autre dossier, c'est un autre parc : le cache décrit celui d'avant.
    /// Même frais d'une minute, il faut réinterroger.
    @Test func unDossierDifférentPasseOutreLeTTL() {
        let frais = now.addingTimeInterval(-60)
        #expect(UpdateCheckPolicy.shouldCheckAfterSelection(
            gameFolderChanged: true, autoCheckEnabled: true,
            lastSuccess: frais, now: now, ttl: ttl))
    }

    /// Re-choisir le même dossier retombe sous la règle du lancement — sinon
    /// un aller-retour dans les Réglages coûte une passe sur tout le parc.
    @Test func leMêmeDossierRetombeSousLeTTL() {
        let frais = now.addingTimeInterval(-(11 * 3600))
        #expect(!UpdateCheckPolicy.shouldCheckAfterSelection(
            gameFolderChanged: false, autoCheckEnabled: true,
            lastSuccess: frais, now: now, ttl: ttl))
        let périmé = now.addingTimeInterval(-(13 * 3600))
        #expect(UpdateCheckPolicy.shouldCheckAfterSelection(
            gameFolderChanged: false, autoCheckEnabled: true,
            lastSuccess: périmé, now: now, ttl: ttl))
    }

    /// Le réglage prime sur tout, **y compris sur un changement de dossier** :
    /// choisir un dossier n'est pas consentir à du réseau.
    @Test func leRéglageCoupéPrimeMêmeSurUnChangement() {
        #expect(!UpdateCheckPolicy.shouldCheckAfterSelection(
            gameFolderChanged: true, autoCheckEnabled: false,
            lastSuccess: nil, now: now, ttl: ttl))
        #expect(!UpdateCheckPolicy.shouldCheckAfterSelection(
            gameFolderChanged: false, autoCheckEnabled: false,
            lastSuccess: nil, now: now, ttl: ttl))
    }

    /// Premier lancement sur un dossier jamais interrogé : rien à ménager.
    @Test func jamaisVérifiéEtMêmeDossierPasseQuandMême() {
        #expect(UpdateCheckPolicy.shouldCheckAfterSelection(
            gameFolderChanged: false, autoCheckEnabled: true,
            lastSuccess: nil, now: now, ttl: ttl))
    }

}
