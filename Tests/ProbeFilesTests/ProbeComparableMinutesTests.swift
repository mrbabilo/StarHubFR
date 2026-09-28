import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeComparableMinutesTests {
    private func sessions() throws -> ProbeSessions {
        ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                             costs: try Fixture.data("mod-costs.jsonl"))
    }

    private func minute(at: String, location: String? = "Farm", inactive: Int = 0,
                        menuShare: Double? = nil, gameTime: Int? = 650,
                        tickCount: Int = 1000) -> ProbeMinute {
        let json = """
        {"Session":"s","At":"2026-09-28T\(at):00.0000000+02:00","WallSeconds":60,"Fps":30,
         "FrameInterval":{"Count":45,"Avg":30,"P50":30,"P99":50,"Max":60},
         "InactiveTicks":\(inactive),"HeapMB":4000,"LoadedMods":289,
         "Location":\(location.map { "\"\($0)\"" } ?? "null"),
         "MenuTicks":\(menuShare.map { Int(Double(tickCount) * $0) } ?? 0),
         "Tick":{"Count":\(tickCount),"Avg":20,"P50":20,"P99":40,"Max":50},
         "GameTime":\(gameTime.map(String.init) ?? "null")}
        """
        // Clés PascalCase : toujours le décodeur du dépôt.
        return try! ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8))
    }

    private func cost(at: String, patches: Bool) -> ProbeModCostMinute {
        let json = """
        {"Session":"s","At":"2026-09-28T\(at):00.0000000+02:00","WallSeconds":60,"Frames":45,
         "Location":"Farm","PatchesMeasured":\(patches),"Mods":[]}
        """
        return try! ProbeJSON.decoder().decode(ProbeModCostMinute.self, from: Data(json.utf8))
    }

    /// Les minutes réelles de la session 0.4.12 : titre, première en partie
    /// (chargement), puis trois minutes à menu ouvert.
    @Test func realSession0412ExcludesEverything() throws {
        let session = try #require(try sessions().sessions.first { $0.id.hasPrefix("2026-09-28T18:56") })
        let result = ProbeComparableMinutes.filter(session.minutes, costs: session.costs)
        #expect(result.kept.isEmpty)
        #expect(result.exclusions == [.title: 1, .firstAfterTitle: 1, .menuOpen: 3])
    }

    /// Patches : l'état apparié est attaché à chaque minute gardée ; la
    /// comparaison des deux côtés se fait dans `ProbeComparison`
    /// (`patchesMismatch`). La première minute en partie est exclue
    /// (chargement) — la seconde seule est gardée.
    @Test func patchesStateIsAttachedToKeptMinutes() {
        let kept = ProbeComparableMinutes.filter(
            [minute(at: "10:00"), minute(at: "10:01")],
            costs: [cost(at: "10:00", patches: true), cost(at: "10:01", patches: true)])
        #expect(kept.exclusions == [.firstAfterTitle: 1])
        #expect(kept.kept.count == 1)
        #expect(kept.kept.first?.patchesMeasured == true)
        // Aucune ligne de coûts appariée : état inconnu (`nil`), la minute
        // reste gardée — deux inconnus s'accordent.
        let unknown = ProbeComparableMinutes.filter(
            [minute(at: "10:00"), minute(at: "10:01")], costs: [])
        #expect(unknown.kept.count == 1)
        #expect(unknown.kept.first?.patchesMeasured == nil)
    }

    /// Nuit : `GameTime` qui baisse. Égal ou qui monte : pas une nuit (le
    /// relevé à la minute donne deux minutes du même quart d'heure de jeu).
    @Test func nightIsADecreasingGameTime() {
        let days = ProbeComparableMinutes.filter(
            [minute(at: "10:00", gameTime: 1000), minute(at: "10:01", gameTime: 1000),
             minute(at: "10:02", gameTime: 2200), minute(at: "10:03", gameTime: 2600),
             minute(at: "10:04", gameTime: 600), minute(at: "10:05", gameTime: 600)],
            costs: [])
        // 2600→600 baisse (nuit) ; 1000→1000 et 600→600 égaux (gardés).
        #expect(days.exclusions == [.firstAfterTitle: 1, .night: 1])
        #expect(days.kept.count == 4)
    }

    /// Unfocus, menu ≥ 50 %, titre : chacun son compte. Après le titre, la
    /// première minute en partie est exclue (chargement), la suivante gardée.
    @Test func guardsEachCount() {
        let result = ProbeComparableMinutes.filter(
            [minute(at: "10:00", inactive: 5), minute(at: "10:01", menuShare: 0.62),
             minute(at: "10:02", location: nil), minute(at: "10:03"), minute(at: "10:04")],
            costs: [])
        #expect(result.exclusions
                == [.unfocused: 1, .menuOpen: 1, .title: 1, .firstAfterTitle: 1])
        #expect(result.kept.count == 1)
    }

    /// Sonde < 0.4.12 : pas de champ `MenuTicks` du tout — la garde menu
    /// passe (`menuShare == nil`), l'instantané `Menu == null` jouait ce rôle.
    @Test func oldProbeWithoutMenuTicksPassesMenuGuard() throws {
        let json = """
        {"Session":"s","At":"2026-09-27T10:00:00.0000000+02:00","WallSeconds":60,"Fps":30,
         "FrameInterval":{"Count":45,"Avg":30,"P50":30,"P99":50,"Max":60},
         "InactiveTicks":0,"HeapMB":4000,"LoadedMods":289,"Location":"Farm"}
        """
        let oldMinute = try ProbeJSON.decoder().decode(ProbeMinute.self, from: Data(json.utf8))
        #expect(oldMinute.menuShare == nil)   // la preuve de décodage
        let result = ProbeComparableMinutes.filter(
            [oldMinute, minute(at: "10:01", gameTime: nil)], costs: [])
        #expect(result.exclusions == [.firstAfterTitle: 1])
        #expect(result.kept.count == 1)
    }

    /// « Même lieu d'abord » : ≥ 5 minutes comparables de chaque côté dans des
    /// lieux communs → on restreint ; sinon tout compte et le drapeau le dit.
    @Test func sharedLocationsRestrictWhenEnoughMinutes() {
        func kept(_ at: String, location: String) -> ProbeComparableMinute {
            ProbeComparableMinute(minute: minute(at: at, location: location), patchesMeasured: nil)
        }
        let farmA = (0..<6).map { kept("10:0\($0)", location: "Farm") }
        let farmB = (0..<6).map { kept("11:0\($0)", location: "Farm") }
        let mineA = (0..<2).map { kept("12:0\($0)", location: "Mine") }
        let mineB = (0..<2).map { kept("13:0\($0)", location: "Mine") }
        let town = kept("14:00", location: "Town")
        let restricted = ProbeComparableMinutes.restrictToSharedLocations(farmA + mineA + [town], farmB + mineB)
        #expect(restricted.restricted)
        // Farm et Mine sont présents des deux côtés ; Town, d'un seul, sort.
        #expect(restricted.a.count == 8 && restricted.b.count == 8)
        let flagged = ProbeComparableMinutes.restrictToSharedLocations(farmA, mineB)
        #expect(!flagged.restricted)
        #expect(flagged.a.count == 6 && flagged.b.count == 2)
    }

    /// La chronologie montre **chaque** minute écartée à sa place, avec sa
    /// raison : les comptes seuls ne disent pas quand.
    @Test func excludedMinutesKeepTheirReasonAndOrder() {
        let result = ProbeComparableMinutes.filter(
            [minute(at: "10:00", inactive: 5), minute(at: "10:01", menuShare: 0.62),
             minute(at: "10:02", location: nil), minute(at: "10:03"), minute(at: "10:04")],
            costs: [])
        #expect(result.excluded.map(\.reason) == [.unfocused, .menuOpen, .title, .firstAfterTitle])
        #expect(result.excluded.map { String($0.minute.at.dropFirst(11).prefix(5)) }
                == ["10:00", "10:01", "10:02", "10:03"])
        #expect(result.excluded.count == result.exclusions.values.reduce(0, +))
    }

    /// Les gardes tournent **une fois par session** : un segment qui commence
    /// après une coupure n'a pas de « première minute en partie » à lui. Sa
    /// part se prend dans le filtrage de la session (sinon sa première minute
    /// passait pour un chargement).
    @Test func restrictingKeepsTheSessionWideVerdicts() {
        let minutes = [minute(at: "10:00"), minute(at: "10:01"), minute(at: "10:02"), minute(at: "10:03")]
        let whole = ProbeComparableMinutes.filter(minutes, costs: [])
        let tail = whole.restricted(to: Array(minutes[2...]))
        #expect(tail.kept.map(\.minute) == Array(minutes[2...]))
        #expect(tail.excluded.isEmpty && tail.exclusions.isEmpty)
        let head = whole.restricted(to: Array(minutes[..<2]))
        #expect(head.exclusions == [.firstAfterTitle: 1] && head.kept.count == 1)
    }
}
