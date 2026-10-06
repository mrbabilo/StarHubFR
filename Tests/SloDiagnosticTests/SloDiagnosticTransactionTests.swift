import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct SloDiagnosticTransactionTests {
    private let original = Data(#"{"Keep":{"Nested":[1,"x",true]},"EnableDetailedDiagnostics":false}"#.utf8)

    private func snapshot(original: SloDiagnosticConfigState = .bytes(Data("original".utf8)),
                          diagnostic: Data = Data("diagnostic".utf8),
                          roots: [SloDiagnosticRootSnapshot] = [
                            .init(logicalName: "SLO", initialPhysicalName: ".SLO",
                                  activePhysicalName: "SLO", initiallyEnabled: false)
                          ]) -> SloDiagnosticSnapshot {
        SloDiagnosticSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: Date(timeIntervalSince1970: 100),
            modsRootURL: URL(fileURLWithPath: "/Game/Mods"),
            roots: roots,
            initialConfigURL: URL(fileURLWithPath: "/Game/Mods/.SLO/config.json"),
            activeConfigURL: URL(fileURLWithPath: "/Game/Mods/SLO/config.json"),
            originalConfig: original,
            diagnosticConfig: diagnostic,
            acceptedDiagnosticSHA256: [SloDiagnosticTransaction.sha256(diagnostic)],
            logBookmark: .init(size: 12, sha256: "abc", modified: Date(timeIntervalSince1970: 90)),
            knownProbeSessionIDs: ["old-session"]
        )
    }

    @Test func missingConfigCreatesOnlyTwoBooleanKeys() throws {
        let prepared = try SloDiagnosticTransaction.prepare(original: nil, version: "1.0.0")
        #expect(prepared.original == .missing)
        #expect(prepared.sha256 == SloDiagnosticTransaction.sha256(prepared.data))
        let object = try #require(JSONSerialization.jsonObject(with: prepared.data) as? [String: Any])
        #expect(object.count == 2)
        #expect(object[SloDiagnosticContract.detailedDiagnosticsKey] as? Bool == true)
        #expect(object[SloDiagnosticContract.performanceMeasurementKey] as? Bool == true)
    }

    @Test func json5AndUnknownNestedValuesSurviveSemantically() throws {
        let source = Data(#"""
        {
          // commentaire permis par SLO
          "Keep": { "Nested": [1, "x", true], },
          "EnableDetailedDiagnostics": false,
        }
        """#.utf8)
        let prepared = try SloDiagnosticTransaction.prepare(original: source, version: "1.0.0")
        #expect(prepared.original == .bytes(source))
        let object = try #require(JSONSerialization.jsonObject(with: prepared.data) as? [String: Any])
        let keep = try #require(object["Keep"] as? [String: Any])
        let nested = try #require(keep["Nested"] as? [Any])
        #expect(nested.count == 3)
        #expect(nested[0] as? Int == 1)
        #expect(nested[1] as? String == "x")
        #expect(nested[2] as? Bool == true)
        #expect(object[SloDiagnosticContract.detailedDiagnosticsKey] as? Bool == true)
        #expect(object[SloDiagnosticContract.performanceMeasurementKey] as? Bool == true)
    }

    @Test func scalarAndInvalidDiagnosticValuesAreRefused() {
        for scalar in ["1", "true", "null", "[]"] {
            #expect(throws: SloDiagnosticTransactionError.invalidConfig) {
                try SloDiagnosticTransaction.prepare(original: Data(scalar.utf8), version: "1.0.0")
            }
        }
        for value in ["1", "0", #""true""#, "null"] {
            let data = Data("{\"EnableDetailedDiagnostics\":\(value)}".utf8)
            #expect(throws: SloDiagnosticTransactionError.invalidDiagnosticValue(
                SloDiagnosticContract.detailedDiagnosticsKey)) {
                try SloDiagnosticTransaction.prepare(original: data, version: "1.0.0")
            }
        }
    }

    @Test func oldSloVersionIsRefused() {
        #expect(throws: SloDiagnosticTransactionError.outdatedVersion("0.9.9")) {
            try SloDiagnosticTransaction.prepare(original: nil, version: "0.9.9")
        }
    }

    @Test func restoreDecisionNeverOverwritesUnexpectedBytes() {
        let diagnostic = Data("diagnostic".utf8)
        let original = Data("original".utf8)
        let plan = snapshot(original: .bytes(original), diagnostic: diagnostic)
        #expect(SloDiagnosticTransaction.restoreDecision(snapshot: plan, current: diagnostic)
                == .restore(original))
        #expect(SloDiagnosticTransaction.restoreDecision(snapshot: plan, current: original)
                == .alreadyRestored)
        #expect(SloDiagnosticTransaction.restoreDecision(snapshot: plan,
                                                         current: Data("changed".utf8)) == .conflict)
        #expect(SloDiagnosticTransaction.restoreDecision(snapshot: plan, current: nil) == .conflict)

        let missing = snapshot(original: .missing, diagnostic: diagnostic)
        #expect(SloDiagnosticTransaction.restoreDecision(snapshot: missing, current: diagnostic) == .remove)
        #expect(SloDiagnosticTransaction.restoreDecision(snapshot: missing, current: nil) == .alreadyRestored)
    }

    @Test func snapshotDeduplicatesSharedPackRoot() {
        let root = SloDiagnosticRootSnapshot(logicalName: "Pack", initialPhysicalName: ".Pack",
                                             activePhysicalName: "Pack", initiallyEnabled: false)
        #expect(snapshot(roots: [root, root]).roots == [root])
    }

    @Test func snapshotRoundTripsEveryRecoveryBoundary() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("slo-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        var plan = snapshot()

        try SloDiagnosticSnapshotStore.save(plan, in: base)
        #expect(try SloDiagnosticSnapshotStore.load(from: base) == plan)

        plan.activatedRootFolderNames.insert("SLO")
        try SloDiagnosticSnapshotStore.save(plan, in: base)
        #expect(try SloDiagnosticSnapshotStore.load(from: base)?.activatedRootFolderNames == ["SLO"])

        plan.configWritten = true
        plan.launchRequestedAt = Date(timeIntervalSince1970: 110)
        plan.gameSeen = true
        try SloDiagnosticSnapshotStore.save(plan, in: base)
        #expect(try SloDiagnosticSnapshotStore.load(from: base) == plan)

        plan.configRestored = true
        plan.restoredRootFolderNames.insert("SLO")
        try SloDiagnosticSnapshotStore.save(plan, in: base)
        #expect(try SloDiagnosticSnapshotStore.load(from: base) == plan)

        try SloDiagnosticSnapshotStore.clear(in: base)
        try SloDiagnosticSnapshotStore.clear(in: base)
        #expect(try SloDiagnosticSnapshotStore.load(from: base) == nil)
    }

    @Test func corruptSnapshotThrowsAndPausedRestorationReadsInitialPath() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("slo-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: SloDiagnosticSnapshotStore.fileURL(in: base))
        #expect(throws: (any Error).self) { try SloDiagnosticSnapshotStore.load(from: base) }

        let plan = snapshot()
        #expect(SloDiagnosticTransaction.currentConfigURL(snapshot: plan, rootIsEnabled: true)
                == plan.activeConfigURL)
        #expect(SloDiagnosticTransaction.currentConfigURL(snapshot: plan, rootIsEnabled: false)
                == plan.initialConfigURL)
    }
}
