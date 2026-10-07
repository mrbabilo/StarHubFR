import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ProbeLifecycleContractTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func gmcmApiIsRequestedOnlyAfterEveryModIsInitialized() throws {
        let source = try String(contentsOf: repository
            .appendingPathComponent("companion/StarHubFR.Probe/ModEntry.cs"), encoding: .utf8)
        let launch = try #require(source.range(of: "helper.Events.GameLoop.GameLaunched +="))
        let configMenu = try #require(source.range(of: "ConfigMenu.Initialize"))

        #expect(configMenu.lowerBound > launch.lowerBound)
    }

    @Test func errorHistoryUsesStableSmapiLaunchDate() throws {
        let log = "[11:06:03 TRACE SMAPI] Log started at 2026-10-07T09:06:03 UTC\r\n"
        let firstWrite = Date(timeIntervalSince1970: 20)
        let laterWrite = Date(timeIntervalSince1970: 30)
        let first = SmapiHealthFold.logIdentityDate(in: log, modificationDate: firstWrite)
        let later = SmapiHealthFold.logIdentityDate(in: log, modificationDate: laterWrite)
        #expect(first == later)
        #expect(first != firstWrite)

        let source = try String(contentsOf: repository
            .appendingPathComponent("StarHubTH/StarHubTHViewModel.swift"), encoding: .utf8)
        #expect(source.contains("SmapiHealthFold.logIdentityDate"))
    }
}
