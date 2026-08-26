import Foundation
import Testing
@testable import StarHubTHCore

/// B2-T5 — l'âge de la dernière mise à jour, affiché à côté de sa date sur la
/// fiche du mod. Le seuil d'un an révolu est la règle : en deçà, la date se
/// lit fraîche d'elle-même et l'âge serait du bruit ; au-delà, il devient le
/// signal (« ce mod dort depuis cinq ans »). Le texte vient de
/// `RelativeDateTimeFormatter` — rendu vérifié sur la machine de référence :
/// « il y a 5 ans » (fr), « 5 years ago » (en).
@Suite struct LastUpdateAgeTests {

    /// 2027-01-15, fixe : la frontière doit être déterministe, pas tributaire
    /// de la date du jour où le test tourne.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Pas d'âge avant un an révolu")
    func noAgeBeforeOneYear() {
        #expect(LastUpdateAge.ageText(for: now, now: now) == nil)
        #expect(LastUpdateAge.ageText(for: now.addingTimeInterval(-364 * 86_400), now: now) == nil)
    }

    @Test("L'âge apparaît dès qu'un an est révolu")
    func ageFromOneYear() {
        #expect(LastUpdateAge.ageText(for: now.addingTimeInterval(-366 * 86_400), now: now) != nil)
        #expect(LastUpdateAge.ageText(for: now.addingTimeInterval(-370 * 86_400),
                                      now: now, locale: Locale(identifier: "fr")) == "il y a 1 an")
    }

    @Test("Le texte est celui du formateur relatif, en années")
    func relativeText() {
        #expect(LastUpdateAge.ageText(for: now.addingTimeInterval(-5 * 365.25 * 86_400),
                                      now: now, locale: Locale(identifier: "fr")) == "il y a 5 ans")
        #expect(LastUpdateAge.ageText(for: now.addingTimeInterval(-5 * 365.25 * 86_400),
                                      now: now, locale: Locale(identifier: "en")) == "5 years ago")
    }
}
