import Testing
import Foundation
@testable import StarHubTHCore

/// Un zéro ne vaut « tout est à jour » que mesuré par une passe complète,
/// sans mod resté sans verdict (I, suite de l'audit UX du 2026-10-02).
@Suite struct UpdateCheckVerdictTests {

    private let checked = Date(timeIntervalSince1970: 1_790_940_332)

    @Test func unCompteNonNulResteEnAttente() {
        #expect(UpdateCheckVerdict.resolve(pending: 3, lastCheckedAt: nil,
                                           unverifiableCount: nil) == .pending(3))
    }

    /// Le défaut d'origine : zéro sans aucune passe aboutie.
    @Test func zeroSansPasseAboutieNAffirmeRien() {
        #expect(UpdateCheckVerdict.resolve(pending: 0, lastCheckedAt: nil,
                                           unverifiableCount: 0) == .neverChecked)
    }

    @Test func zeroMesureSansInverifiableEstAJour() {
        #expect(UpdateCheckVerdict.resolve(pending: 0, lastCheckedAt: checked,
                                           unverifiableCount: 0)
                == .upToDate(checkedAt: checked))
    }

    /// Le cas voisin qui ne doit PAS donner le quitus : des mods sans verdict.
    @Test func desInverifiablesRetiennentLeQuitus() {
        #expect(UpdateCheckVerdict.resolve(pending: 0, lastCheckedAt: checked,
                                           unverifiableCount: 12)
                == .verifiableUpToDate(checkedAt: checked))
    }

    /// Après relance : horodatage connu, invérifiables inconnus (non
    /// persistés) — une liste vide n'est pas une liste sans mod.
    @Test func inverifiablesInconnusRetiennentLeQuitus() {
        #expect(UpdateCheckVerdict.resolve(pending: 0, lastCheckedAt: checked,
                                           unverifiableCount: nil)
                == .verifiableUpToDate(checkedAt: checked))
    }

    @Test func lAgeSuitLaLangueDeLInterface() {
        let now = checked.addingTimeInterval(3 * 3600)
        let fr = UpdateCheckVerdict.ageText(since: checked, now: now,
                                            locale: Locale(identifier: "fr"))
        let en = UpdateCheckVerdict.ageText(since: checked, now: now,
                                            locale: Locale(identifier: "en"))
        #expect(fr == "il y a 3 heures")
        #expect(en == "3 hours ago")
    }

    /// Horloge reculée : jamais « dans 2 minutes » pour une passe passée.
    @Test func uneDateFutureSeLitMaintenant() {
        let future = UpdateCheckVerdict.ageText(since: checked.addingTimeInterval(120),
                                                now: checked,
                                                locale: Locale(identifier: "en"))
        #expect(future == "now")
    }
}
