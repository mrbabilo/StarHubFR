import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeSessionsTests {
    private func sessions() throws -> ProbeSessions {
        ProbeSessions.decode(timings: try Fixture.data("timings.jsonl"),
                             costs: try Fixture.data("mod-costs.jsonl"))
    }

    /// Les deux fichiers se rejoignent par l'identifiant de session : cinq
    /// sessions côté trames, trois côté coûts, deux en commun (20:30, 18:56).
    @Test func sessionsAreSeparatedByTheirIdentifierAndSortedByDate() throws {
        let result = try sessions()
        // Tri par date de démarrage : le 26 à 20:30 précède le 28.
        #expect(result.sessions.map { String($0.id.prefix(16)) }
                == ["2026-09-26T01:38", "2026-09-26T01:53", "2026-09-26T02:33",
                    "2026-09-26T20:30", "2026-09-28T18:56", "2026-09-28T19:21"])
        #expect(result.sessions.map(\.minutes.count) == [8, 11, 0, 8, 5, 3])
        #expect(result.sessions.map(\.costs.count) == [0, 0, 6, 8, 5, 0])
    }

    /// Les lignes 0.4.12+ portent `MenuTicks` — **toutes**, écran titre
    /// compris (442/444 à 18:59:31) ; les anciennes non.
    @Test func menuShareComesFromMenuTicksAndTicks() throws {
        let result = try sessions()
        let recent = try #require(result.sessions.first { $0.id.hasPrefix("2026-09-28T18:56") })
        let shares = recent.minutes.compactMap(\.menuShare)
        #expect(shares.count == 5)
        #expect(abs(shares[0] - 442.0 / 444.0) < 0.001)
        let old = result.sessions[0]
        #expect(old.minutes.allSatisfy { $0.menuShare == nil && $0.menuTicks == nil })
    }

    /// La dernière ligne de chaque fichier est une ligne réelle coupée net :
    /// comptée, pas levée, et les autres lignes restent lues.
    @Test func aTruncatedLineIsCountedNotThrown() throws {
        #expect(try sessions().unreadableLines == 2)
    }

    /// Les lignes de la v0.2 n'ont pas `InactiveTicks` : elles se lisent quand
    /// même, et ne sont pas prises pour des minutes sans focus.
    @Test func oldLinesWithoutInactiveTicksDecode() throws {
        let old = try sessions().sessions[0]
        #expect(old.minutes.allSatisfy { $0.inactiveTicks == nil && !$0.isUnfocused })
    }

    @Test func unfocusedMinutesAreFlagged() throws {
        let session = try sessions().sessions[1]
        #expect(session.minutes.filter(\.isUnfocused).count == 6)
    }

    /// « Écran titre » vient du lieu, pas de la position : un retour au titre
    /// en milieu de session (session 01:38) est signalé aussi.
    @Test func titleMinutesAreFlaggedWhereverTheyFall() throws {
        let minutes = try sessions().sessions[0].minutes
        let title = minutes.indices.filter { minutes[$0].isAtTitle }
        #expect(title.count == 3)
        #expect(title.contains { $0 > 0 })
    }

    /// `SelfMs` inclut le temps des patches (`FrameTimings.cs:226`) ; une
    /// ligne d'avant la v0.4.1 n'a pas `PatchMs` : tout son temps est événement.
    @Test func eventOnlyTimeSubtractsPatchTime() throws {
        let all = try sessions().sessions
        let old = try #require(all[2].costs.first?.mods.first)
        #expect(old.patchMs == nil)
        #expect(old.eventOnlyMs == old.selfMs)
        let recent = try #require(all[3].costs.flatMap(\.mods).first { ($0.patchMs ?? 0) > 0 })
        #expect(recent.eventOnlyMs == recent.selfMs - (recent.patchMs ?? 0))
    }

    /// .NET écrit 7 décimales. `ISO8601DateFormatter` (macOS 26) les lit, mais
    /// au-delà il **perd la fraction sans erreur** (`…26.914583012345` → `…26.0`) :
    /// la troncature à 3 décimales est ce qui protège.
    @Test func probeTimestampsWithSevenDecimalsParse() throws {
        let reference = ISO8601DateFormatter()
        reference.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try #require(reference.date(from: "2026-09-26T16:47:26.914Z"))
        #expect(ProbeDate.parse("2026-09-26T18:47:26.9145830+02:00") == expected)
        #expect(ProbeDate.parse("2026-09-26T18:47:26.914583012345+02:00") == expected)
        #expect(ProbeDate.parse("2026-09-26T18:47:26+02:00") != nil)
        #expect(ProbeDate.parse("pas une date") == nil)
    }

    /// Pas de fichier : pas de session, pas d'erreur.
    @Test func missingFilesGiveNoSession() {
        let result = ProbeSessions.decode(timings: nil, costs: nil)
        #expect(result.sessions.isEmpty)
        #expect(result.unreadableLines == 0)
    }
}
