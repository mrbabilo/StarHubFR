import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct SloDiagnosticSourcesTests {
    private let launch = Date(timeIntervalSince1970: 1_000)

    private func snapshot(known: Set<String> = [], accepted: Set<String> = ["diagnostic"])
        -> SloDiagnosticSnapshot {
        SloDiagnosticSnapshot(
            startedAt: launch.addingTimeInterval(-10), launchRequestedAt: launch,
            modsRootURL: URL(fileURLWithPath: "/Game/Mods"), roots: [],
            initialConfigURL: URL(fileURLWithPath: "/Game/Mods/SLO/config.json"),
            activeConfigURL: URL(fileURLWithPath: "/Game/Mods/SLO/config.json"),
            originalConfig: .missing, diagnosticConfig: Data("diagnostic config".utf8),
            acceptedDiagnosticSHA256: accepted, logBookmark: nil,
            knownProbeSessionIDs: known)
    }

    private func bookmark(_ text: String, modified: Date? = nil) -> SloDiagnosticLogBookmark {
        let data = Data(text.utf8)
        return SloDiagnosticLogBookmark(size: data.count,
                                        sha256: SloDiagnosticTransaction.sha256(data),
                                        modified: modified)
    }

    @Test func bookmarkReadsExactBytesAndMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("SMAPI-latest.txt")
        let data = Data("avant\n".utf8)
        try data.write(to: url)
        let result = try #require(SloDiagnosticSourceReader.bookmark(logURL: url))
        #expect(result.size == data.count)
        #expect(result.sha256 == SloDiagnosticTransaction.sha256(data))
        #expect(result.modified != nil)
    }

    @Test func appendedLogReturnsOnlyNewSuffix() {
        let old = "old session\n"
        let current = Data((old + "[OPTIMIZER CONFIG] profile=3\n").utf8)
        #expect(SloDiagnosticSourceReader.newLog(
            current: current, bookmark: bookmark(old), modified: launch,
            launchRequestedAt: launch) == "[OPTIMIZER CONFIG] profile=3\n")
    }

    @Test func replacementLogStartsAtZero() {
        let old = "an older and substantially longer session\n"
        let replacement = Data("new session\n".utf8)
        #expect(SloDiagnosticSourceReader.newLog(
            current: replacement, bookmark: bookmark(old), modified: launch.addingTimeInterval(-4),
            launchRequestedAt: launch) == "new session\n")
    }

    @Test func unchangedLogProducesNoSession() {
        let text = "same\n"
        #expect(SloDiagnosticSourceReader.newLog(
            current: Data(text.utf8), bookmark: bookmark(text), modified: launch,
            launchRequestedAt: launch) == nil)
    }

    @Test func oldReplacementIsRejected() {
        #expect(SloDiagnosticSourceReader.newLog(
            current: Data("replacement".utf8), bookmark: bookmark("old"),
            modified: launch.addingTimeInterval(-6), launchRequestedAt: launch) == nil)
    }

    @Test func changedPrefixIsReplacementRatherThanSuffix() {
        let current = Data("different prefix plus more bytes".utf8)
        #expect(SloDiagnosticSourceReader.newLog(
            current: current, bookmark: bookmark("old"), modified: launch,
            launchRequestedAt: launch) == "different prefix plus more bytes")
    }

    private func session(_ id: String) -> ProbeSession {
        ProbeSession(id: id, minutes: [], costs: [])
    }

    private func inventory(_ session: String, at: Date, sloSha: String?,
                           includeProbe: Bool = true) -> ProbeInventoryLaunch {
        var mods = [ProbeInventoryEntry(modId: SloDiagnosticContract.uniqueId,
                                        version: "1.0.0", configSha: sloSha)]
        if includeProbe {
            mods.append(ProbeInventoryEntry(modId: ModPresence.probeId,
                                            version: "1.0.0", configSha: nil))
        }
        return ProbeInventoryLaunch(session: session, at: at, probe: "1.0.0", mods: mods)
    }

    private func load(_ session: String) -> ProbeLoadRecord {
        ProbeLoadRecord(kind: .launch, session: session, atText: session,
                        at: ProbeDate.parse(session), probeVersion: "1.0.0", complete: true,
                        reload: false, saveName: nil, patchesMeasured: true,
                        saveBytes: nil, saveDate: nil,
                        milestones: [.init(name: "L0", ms: 0), .init(name: "L4", ms: 10)],
                        phases: [], final: nil,
                        health: .init(packSeam: "ok", assetHook: "ok", loadHook: "ok",
                                      offThreadSections: 0))
    }

    @Test func selectsNewExactSessionAndFiltersEverySource() throws {
        let old = "1970-01-01T00:15:00Z"
        let selected = "1970-01-01T00:16:42Z"
        let result = SloDiagnosticCorrelation.select(
            snapshot: snapshot(known: [old]),
            sessions: ProbeSessions(sessions: [session(old), session(selected)], unreadableLines: 2),
            inventory: (launches: [inventory(old, at: launch, sloSha: "diagnostic"),
                                   inventory(selected, at: launch.addingTimeInterval(2),
                                             sloSha: "diagnostic")], changes: [], unreadable: 3),
            loads: (records: [load(old), load(selected)], unreadable: 4))
        let candidate = try #require(result.candidate)
        #expect(candidate.selectedSessionId == selected)
        #expect(candidate.configMatch == .exact)
        #expect(candidate.input.session?.id == selected)
        #expect(candidate.input.loads.map(\.session) == [selected])
        #expect(candidate.input.inventory?.session == selected)
        #expect(result.ambiguousNewSessions.isEmpty)
        #expect(result.unreadableLines == 9)
    }

    @Test func rejectsKnownPrelaunchAndIncompleteInventories() {
        let known = "1970-01-01T00:16:40Z"
        let prelaunch = "1970-01-01T00:16:30Z"
        let missingProbe = "1970-01-01T00:16:43Z"
        let result = SloDiagnosticCorrelation.select(
            snapshot: snapshot(known: [known]),
            sessions: ProbeSessions(sessions: [session(known), session(prelaunch),
                                                session(missingProbe)], unreadableLines: 0),
            inventory: (launches: [inventory(known, at: launch, sloSha: "diagnostic"),
                                   inventory(prelaunch, at: launch.addingTimeInterval(-10),
                                             sloSha: "diagnostic"),
                                   inventory(missingProbe, at: launch.addingTimeInterval(3),
                                             sloSha: "diagnostic", includeProbe: false)],
                        changes: [], unreadable: 0),
            loads: (records: [], unreadable: 0))
        #expect(result.candidate == nil)
        #expect(result.ambiguousNewSessions.isEmpty)
    }

    @Test func surfacesNormalizationCandidateWithoutAcceptingItAsExact() throws {
        let id = "1970-01-01T00:16:42Z"
        let result = SloDiagnosticCorrelation.select(
            snapshot: snapshot(), sessions: ProbeSessions(sessions: [session(id)], unreadableLines: 0),
            inventory: (launches: [inventory(id, at: launch, sloSha: "normalized")],
                        changes: [], unreadable: 0),
            loads: (records: [], unreadable: 0))
        #expect(try #require(result.candidate).configMatch
                == .normalizationCandidate(sha256: "normalized"))
    }

    @Test func multipleBestCandidatesRemainAmbiguous() {
        let a = "1970-01-01T00:16:42Z"
        let b = "1970-01-01T00:16:44Z"
        let result = SloDiagnosticCorrelation.select(
            snapshot: snapshot(), sessions: ProbeSessions(sessions: [session(a), session(b)],
                                                           unreadableLines: 0),
            inventory: (launches: [inventory(a, at: launch, sloSha: "diagnostic"),
                                   inventory(b, at: launch.addingTimeInterval(4),
                                             sloSha: "diagnostic")],
                        changes: [], unreadable: 0),
            loads: (records: [], unreadable: 0))
        #expect(result.candidate == nil)
        #expect(result.ambiguousNewSessions == [a, b])
    }

    @Test func exactCandidateOutranksNormalizationCandidate() throws {
        let normalized = "1970-01-01T00:16:42Z"
        let exact = "1970-01-01T00:16:44Z"
        let result = SloDiagnosticCorrelation.select(
            snapshot: snapshot(), sessions: ProbeSessions(
                sessions: [session(normalized), session(exact)], unreadableLines: 0),
            inventory: (launches: [inventory(normalized, at: launch, sloSha: "normalized"),
                                   inventory(exact, at: launch, sloSha: "diagnostic")],
                        changes: [], unreadable: 0),
            loads: (records: [], unreadable: 0))
        #expect(try #require(result.candidate).selectedSessionId == exact)
    }
}
