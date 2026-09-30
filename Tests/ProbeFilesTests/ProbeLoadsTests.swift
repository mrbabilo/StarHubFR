import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ProbeLoadsTests {
    static func fixture() throws -> [ProbeLoadRecord] {
        ProbeLoadRecords.decode(try Fixture.data("loads.jsonl")).records
    }

    @Test func truncatedLineIsCounted() throws {
        let result = ProbeLoadRecords.decode(try Fixture.data("loads.jsonl"))
        #expect(result.records.count == 5)
        #expect(result.unreadable == 1)
    }

    @Test func launchDecodesWithEscapedSession() throws {
        let launch = try #require(try Self.fixture().first)
        #expect(launch.kind == .launch)
        #expect(launch.session == "2026-09-30T20:00:00.0000000+02:00")
        #expect(launch.complete)
        #expect(launch.totalMs == 57_000)
        #expect(launch.phases.count == 4)
        #expect(launch.phases[2].costs.first?.kind == .event)
        #expect(launch.health.packSeam == "ok")
    }

    @Test func saveCarriesSizeFinalAndPhasesUpToS9() throws {
        let save = try #require(try Self.fixture().dropFirst().first)
        #expect(save.kind == .save)
        #expect(save.saveName == "TestOK_444827372")
        #expect(save.saveBytes == 33_922_308)
        #expect(save.totalMs == 82_500)
        #expect(save.final?.menu == "LetterViewerMenu")
        #expect(save.phases.count == 9)
    }

    @Test func incompleteRecordStaysReadable() throws {
        let cut = try Self.fixture()[2]
        #expect(!cut.complete)
        #expect(cut.reload)
    }

    @Test func unknownCostKindDoesNotDropTheLine() throws {
        let line = #"{"Kind":"launch","Session":"s","At":"2026-09-30T20:00:00.0000000+02:00","ProbeVersion":"0.6.1","Complete":true,"Reload":false,"SaveName":null,"PatchesMeasured":false,"SaveBytes":null,"SaveDate":null,"Milestones":[{"Name":"L0","Ms":0},{"Name":"L4","Ms":10}],"Phases":[{"From":"L0","To":"L4","Ms":10,"Costs":[{"Mod":"X","Kind":"future","Label":"?","Ms":1,"AllocMb":0,"Calls":1}]}],"Final":null,"Health":{"PackSeam":"ok","AssetHook":"ok","LoadHook":"ok","OffThreadSections":0},"NewField":1}"#
        let result = ProbeLoadRecords.decode(Data(line.utf8))
        #expect(result.records.count == 1)
        #expect(result.records[0].phases[0].costs.isEmpty)   // genre inconnu écarté, ligne gardée
    }

    @Test func writesLoadsFollowsTheProbeVersion() {
        #expect(ProbeLoadRecords.writesLoads(probeVersion: "0.6.0"))
        #expect(ProbeLoadRecords.writesLoads(probeVersion: "0.10.0"))
        #expect(!ProbeLoadRecords.writesLoads(probeVersion: "0.5.12"))
        #expect(!ProbeLoadRecords.writesLoads(probeVersion: nil))
        #expect(!ProbeLoadRecords.writesLoads(probeVersion: "bogus"))
    }
}

extension ProbeLoadsTests {
    @Test func launchSpansMergeUnventilatedStart() throws {
        let b = ProbeLoadBreakdown.of(try #require(try Self.fixture().first))
        #expect(b.spans.map(\.name) == [.smapiAndMods, .gameLaunched, .firstTick])
        #expect(b.spans[0].ms == 24_800)
        #expect(b.spans[0].costs.isEmpty)
        #expect(b.spans.map(\.ms).reduce(0, +) == 57_000)
    }

    @Test func unattributedIsSpanMinusCosts() throws {
        let b = ProbeLoadBreakdown.of(try #require(try Self.fixture().first))
        let launched = try #require(b.spans.first { $0.name == .gameLaunched })
        #expect(launched.ms == 4_600)
        #expect(abs(launched.unattributedMs - (4_600 - 812.3 - 120.4)) < 0.01)
    }

    @Test func packCountsForThePackNotContentPatcher() throws {
        let b = ProbeLoadBreakdown.of(try #require(try Self.fixture().dropFirst().first))
        let sve = try #require(b.top.first { $0.mod == "FlashShifter.StardewValleyExpandedCP" })
        #expect(sve.isPack)
        #expect(sve.ms == 7_400)
        #expect(b.top.first?.mod == "Pathoschild.AutoForager")
        #expect(!b.top.contains { $0.mod == "Pathoschild.ContentPatcher" })
    }

    @Test func waitingForPlayerIsShownButNeverInTop() throws {
        let b = ProbeLoadBreakdown.of(try #require(try Self.fixture().dropFirst().first))
        let wait = try #require(b.spans.last)
        #expect(wait.name == .waitingForPlayer)
        #expect(wait.ms == 101_000 - 82_500)
    }

    @Test func packSeamMissingIsSaid() throws {
        let line = #"{"Kind":"launch","Session":"s","At":"a","ProbeVersion":"0.6.0","Complete":true,"Reload":false,"SaveName":null,"PatchesMeasured":false,"SaveBytes":null,"SaveDate":null,"Milestones":[],"Phases":[],"Final":null,"Health":{"PackSeam":"missing","AssetHook":"ok","LoadHook":"ok","OffThreadSections":0}}"#
        let record = try #require(ProbeLoadRecords.decode(Data(line.utf8)).records.first)
        #expect(ProbeLoadBreakdown.of(record).packSeamMissing)
    }
}
