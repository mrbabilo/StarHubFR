import Foundation
import Testing
@testable import StarHubTHCore

@Suite("Taille du texte")
struct TextScaleTests {
    private func defaults() -> UserDefaults {
        let name = "TextScaleTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func sansReglageLeTexteEstNormal() {
        #expect(TextScale.stored(in: defaults()) == .normal)
    }

    @Test func leCranEnregistreEstRelu() {
        let d = defaults()
        d.set(TextScale.large.rawValue, forKey: TextScale.defaultsKey)
        #expect(TextScale.stored(in: d) == .large)
    }

    @Test func uneValeurInconnueVautNormal() {
        let d = defaults()
        d.set("gigantesque", forKey: TextScale.defaultsKey)
        #expect(TextScale.stored(in: d) == .normal)
    }

    @Test func lesCransGrossissentDansLOrdre() {
        let f = TextScale.allCases.map(\.factor)
        #expect(f == f.sorted())
        #expect(TextScale.normal.factor == 1)
    }
}
