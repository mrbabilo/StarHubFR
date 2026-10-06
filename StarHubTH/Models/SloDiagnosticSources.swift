import Foundation

public enum SloDiagnosticConfigMatch: Equatable, Sendable {
    case exact
    case normalizationCandidate(sha256: String)
}

public struct SloDiagnosticProbeCandidate: Equatable, Sendable {
    public let input: SloDiagnosticProbeInput
    public let selectedSessionId: String
    public let configMatch: SloDiagnosticConfigMatch

    public init(input: SloDiagnosticProbeInput, selectedSessionId: String,
                configMatch: SloDiagnosticConfigMatch) {
        self.input = input
        self.selectedSessionId = selectedSessionId
        self.configMatch = configMatch
    }
}

public struct SloDiagnosticCorrelationResult: Equatable, Sendable {
    public let candidate: SloDiagnosticProbeCandidate?
    public let ambiguousNewSessions: [String]
    public let unreadableLines: Int

    public init(candidate: SloDiagnosticProbeCandidate?, ambiguousNewSessions: [String],
                unreadableLines: Int) {
        self.candidate = candidate
        self.ambiguousNewSessions = ambiguousNewSessions
        self.unreadableLines = unreadableLines
    }
}

public enum SloDiagnosticSourceReader {
    private static let clockTolerance: TimeInterval = 5

    public static func bookmark(logURL: URL) -> SloDiagnosticLogBookmark? {
        guard let data = FileManager.default.contents(atPath: logURL.path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        return SloDiagnosticLogBookmark(
            size: data.count, sha256: SloDiagnosticTransaction.sha256(data),
            modified: attributes?[.modificationDate] as? Date)
    }

    /// Rend uniquement les octets écrits après la borne, ou tout le fichier
    /// si SMAPI l'a remplacé pendant ce lancement. Une date ancienne refuse
    /// le remplacement pour ne jamais analyser la session précédente.
    public static func newLog(current: Data?, bookmark: SloDiagnosticLogBookmark?,
                              modified: Date?, launchRequestedAt: Date) -> String? {
        guard let current else { return nil }
        let currentHash = SloDiagnosticTransaction.sha256(current)
        if currentHash == bookmark?.sha256 { return nil }

        if let bookmark, current.count >= bookmark.size {
            let prefix = current.prefix(bookmark.size)
            if SloDiagnosticTransaction.sha256(Data(prefix)) == bookmark.sha256 {
                let suffix = current.dropFirst(bookmark.size)
                guard !suffix.isEmpty else { return nil }
                return String(data: Data(suffix), encoding: .utf8)
            }
        }

        guard let modified,
              modified >= launchRequestedAt.addingTimeInterval(-clockTolerance) else { return nil }
        return String(data: current, encoding: .utf8)
    }
}

public enum SloDiagnosticCorrelation {
    private static let clockTolerance: TimeInterval = 5

    public static func select(
        snapshot: SloDiagnosticSnapshot,
        sessions: ProbeSessions,
        inventory: (launches: [ProbeInventoryLaunch], changes: [ProbeInventoryChange], unreadable: Int)?,
        loads: (records: [ProbeLoadRecord], unreadable: Int)
    ) -> SloDiagnosticCorrelationResult {
        let unreadable = sessions.unreadableLines + (inventory?.unreadable ?? 0) + loads.unreadable
        guard let requestedAt = snapshot.launchRequestedAt, let inventory else {
            return SloDiagnosticCorrelationResult(candidate: nil, ambiguousNewSessions: [],
                                                  unreadableLines: unreadable)
        }

        let earliest = requestedAt.addingTimeInterval(-clockTolerance)
        let eligibleSessions = sessions.sessions.filter {
            !snapshot.knownProbeSessionIDs.contains($0.id) && ($0.startedAt.map { $0 >= earliest } ?? false)
        }
        var candidates: [SloDiagnosticProbeCandidate] = []
        for session in eligibleSessions {
            let matchingInventory = inventory.launches.filter {
                $0.session == session.id && ($0.at.map { $0 >= earliest } ?? false)
            }
            guard matchingInventory.count == 1, let launch = matchingInventory.first,
                  entry(ModPresence.probeId, in: launch) != nil,
                  let slo = entry(SloDiagnosticContract.uniqueId, in: launch),
                  let sha = slo.configSha else { continue }

            let match: SloDiagnosticConfigMatch
            if snapshot.acceptedDiagnosticSHA256.contains(where: {
                $0.caseInsensitiveCompare(sha) == .orderedSame
            }) {
                match = .exact
            } else {
                match = .normalizationCandidate(sha256: sha)
            }
            let input = SloDiagnosticProbeInput(
                session: session, loads: loads.records.filter { $0.session == session.id },
                inventory: launch)
            candidates.append(SloDiagnosticProbeCandidate(
                input: input, selectedSessionId: session.id, configMatch: match))
        }

        let exact = candidates.filter { $0.configMatch == .exact }
        let best = exact.isEmpty ? candidates : exact
        if best.count == 1 {
            return SloDiagnosticCorrelationResult(candidate: best[0], ambiguousNewSessions: [],
                                                  unreadableLines: unreadable)
        }
        let ambiguous = best.map(\.selectedSessionId).sorted { lhs, rhs in
            let l = ProbeDate.parse(lhs) ?? .distantPast
            let r = ProbeDate.parse(rhs) ?? .distantPast
            return l == r ? lhs < rhs : l < r
        }
        return SloDiagnosticCorrelationResult(candidate: nil, ambiguousNewSessions: ambiguous,
                                              unreadableLines: unreadable)
    }

    private static func entry(_ id: String,
                              in inventory: ProbeInventoryLaunch) -> ProbeInventoryEntry? {
        inventory.mods.first { $0.modId.caseInsensitiveCompare(id) == .orderedSame }
    }
}
