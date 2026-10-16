import Foundation
import Testing
@testable import StarHubTHCore

/// R2 — la date et l'âge du journal SMAPI, dits de la même façon par les
/// Alertes et la Santé, dans la langue de l'app.
@Suite struct SmapiLogSourceTests {

    let fr = Locale(identifier: "fr")
    let en = Locale(identifier: "en")
    /// Construite dans le fuseau local : le formateur de date l'y relit, le
    /// test ne dépend pas du fuseau de la machine.
    let logDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 10, day: 14, hour: 17, minute: 13))!

    @Test("Sans journal lu, pas de ligne")
    func noLogNoLine() {
        #expect(SmapiLogSource(logDate: nil, isStale: true, locale: fr) == nil)
    }

    @Test("La date suit la langue de l'app")
    func dateFollowsAppLanguage() throws {
        let french = try #require(SmapiLogSource(logDate: logDate, isStale: false, locale: fr))
        let english = try #require(SmapiLogSource(logDate: logDate, isStale: false, locale: en))
        #expect(french.date == "14/10/2026 17:13")
        // L'espace avant « PM » dépend de la version d'ICU (fine insécable
        // en local, peut-être autre sur la CI) : on n'épingle pas ce caractère.
        #expect(english.date.hasPrefix("10/14/26, 5:13"))
        #expect(english.date.hasSuffix("PM"))
    }

    @Test("Un journal à jour ne dit pas d'âge")
    func freshLogHasNoAge() throws {
        let source = try #require(SmapiLogSource(logDate: logDate, isStale: false,
                                                 now: logDate.addingTimeInterval(150_000), locale: fr))
        #expect(source.staleAge == nil)
    }

    @Test("Un journal périmé dit son âge, deux unités au plus")
    func staleLogSaysItsAge() throws {
        let now = logDate.addingTimeInterval(150_000)
        #expect(SmapiLogSource(logDate: logDate, isStale: true, now: now, locale: fr)?.staleAge == "1j 18h")
        #expect(SmapiLogSource(logDate: logDate, isStale: true, now: now, locale: en)?.staleAge == "1d 18h")
    }

    @Test("Un journal périmé de quelques secondes dit une minute, jamais zéro")
    func staleAgeHasAOneMinuteFloor() {
        let source = SmapiLogSource(logDate: logDate, isStale: true,
                                    now: logDate.addingTimeInterval(5), locale: fr)
        #expect(source?.staleAge == "1min")
    }
}
