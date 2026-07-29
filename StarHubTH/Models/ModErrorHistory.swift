import Foundation

/// Per-mod, per-version record of the errors and warnings a mod logged.
///
/// Answers the question a player actually has when a mod misbehaves: *is this
/// version worse than the one I had before?* Kept as a summary rather than a
/// full log copy — counts, a first/last seen date, and a few sample messages —
/// so it stays small across hundreds of mods and many launches.
///
/// Pure value types with no I/O, so the merge logic is unit-testable; the
/// ViewModel owns loading and saving.
public struct ModErrorHistory: Codable, Equatable {
    /// One mod version's tally.
    public struct VersionRecord: Codable, Equatable {
        public var version: String
        public var errorCount: Int
        public var warningCount: Int
        public var firstSeen: Date
        public var lastSeen: Date
        /// Distinct messages, capped — enough to recognize the problem without
        /// storing the log.
        public var samples: [String]

        public init(version: String, errorCount: Int = 0, warningCount: Int = 0,
                    firstSeen: Date, lastSeen: Date, samples: [String] = []) {
            self.version = version
            self.errorCount = errorCount
            self.warningCount = warningCount
            self.firstSeen = firstSeen
            self.lastSeen = lastSeen
            self.samples = samples
        }

        public var total: Int { errorCount + warningCount }
    }

    /// Keyed by mod folder name (the same key the install registry uses), then
    /// by version string.
    public var mods: [String: [String: VersionRecord]] = [:]

    public init() {}

    /// Max distinct sample messages kept per version.
    public static let maxSamples = 5

    /// An observation to fold into the history.
    public struct Observation {
        public let mod: String
        public let version: String
        public let message: String
        public let isError: Bool
        public init(mod: String, version: String, message: String, isError: Bool) {
            self.mod = mod
            self.version = version
            self.message = message
            self.isError = isError
        }
    }

    /// Folds one log's observations into the history.
    ///
    /// `at` is the observation time (the log's own date, not "now", so a stale
    /// log doesn't look fresh). Re-merging the same log is **not** idempotent by
    /// design — the caller decides when a log is new; see `record(logDate:)`.
    public mutating func merge(_ observations: [Observation], at date: Date) {
        for obs in observations {
            var byVersion = mods[obs.mod] ?? [:]
            var record = byVersion[obs.version]
                ?? VersionRecord(version: obs.version, firstSeen: date, lastSeen: date)

            if obs.isError { record.errorCount += 1 } else { record.warningCount += 1 }
            record.firstSeen = min(record.firstSeen, date)
            record.lastSeen = max(record.lastSeen, date)

            // Distinct messages only, oldest kept: the first occurrences of a
            // problem are usually the informative ones.
            if record.samples.count < Self.maxSamples,
               !record.samples.contains(obs.message) {
                record.samples.append(obs.message)
            }

            byVersion[obs.version] = record
            mods[obs.mod] = byVersion
        }
    }

    /// Every version recorded for a mod, most recently seen first.
    public func history(for mod: String) -> [VersionRecord] {
        (mods[mod] ?? [:]).values.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Totals across every version of a mod — drives an at-a-glance badge.
    public func totals(for mod: String) -> (errors: Int, warnings: Int) {
        let records = mods[mod]?.values ?? [:].values
        return (records.reduce(0) { $0 + $1.errorCount },
                records.reduce(0) { $0 + $1.warningCount })
    }

    /// Drops versions a mod no longer has, keeping the current one. Called after
    /// an update so the file doesn't grow forever; the current version's tally
    /// survives.
    public mutating func pruneVersions(for mod: String, keeping keep: Set<String>) {
        guard var byVersion = mods[mod] else { return }
        byVersion = byVersion.filter { keep.contains($0.key) }
        if byVersion.isEmpty { mods.removeValue(forKey: mod) } else { mods[mod] = byVersion }
    }

    /// Forgets a mod entirely (uninstalled).
    public mutating func remove(mod: String) {
        mods.removeValue(forKey: mod)
    }
}
