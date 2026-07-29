import Foundation

/// Collapses repetitive SMAPI log lines into families so the Logs view can fold
/// them instead of showing thousands of near-identical entries.
///
/// A real modlist produces ~90 % TRACE lines, dominated by a handful of shapes
/// (`Content Patcher loaded asset 'X' (for the 'Y' content pack).` ×646,
/// `Loaded 'X'` ×396, …). They aren't literal duplicates — the asset name
/// differs every time — so exact-match dedup finds nothing. Normalizing the
/// variable parts away reveals the family they belong to.
///
/// Pure (no I/O, no UI) so it is unit-testable in the Core target.
public enum LogNoise {
    /// How many lines of the same family are needed before folding them. Below
    /// this, folding would hide lines without buying any readability.
    public static let groupingThreshold = 5

    /// A stable key for the family a message belongs to: quoted strings, numbers
    /// and hex ids are masked, so only the message's shape remains.
    ///
    /// `Loaded 'Foo.dll'` and `Loaded 'Bar.dll'` share a signature;
    /// `Loaded 'Foo.dll'` and `Invalidated 3 cache entries.` do not.
    public static func signature(of message: String) -> String {
        // Only the first line: stack traces and multi-line details would make
        // every occurrence unique.
        var s = message
        if let newline = s.firstIndex(where: { $0.isNewline }) {
            s = String(s[..<newline])
        }
        s = s.trimmingCharacters(in: .whitespaces)

        // Order matters: mask quoted spans before digits, otherwise a quoted
        // name containing digits masks to a different shape than one without.
        s = replacing(s, pattern: "'[^']*'", with: "'~'")
        s = replacing(s, pattern: "\"[^\"]*\"", with: "\"~\"")
        s = replacing(s, pattern: "[0-9]+", with: "~")

        // Long messages can still differ far to the right; the head carries the
        // shape, so cap it to keep signatures cheap to compare.
        return String(s.prefix(120))
    }

    private static func replacing(_ string: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let range = NSRange(location: 0, length: (string as NSString).length)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    // MARK: - Grouping by mod

    /// One mod's slice of the log, with the counts needed to flag it in the UI.
    ///
    /// `mod == nil` is the framework bucket (SMAPI and game lines). Keeping it
    /// as a real group matters: two thirds of a real log is framework output,
    /// including errors, so grouping by mod must not make it disappear.
    public struct ModGroup: Identifiable {
        public let mod: String?
        public let lineCount: Int
        public let errorCount: Int
        public let warningCount: Int
        /// Indices into the array that was grouped, in original order.
        public let indices: [Int]

        public var id: String { mod ?? "\u{0000}framework" }
        public var hasProblems: Bool { errorCount > 0 || warningCount > 0 }

        public init(mod: String?, lineCount: Int, errorCount: Int, warningCount: Int, indices: [Int]) {
            self.mod = mod
            self.lineCount = lineCount
            self.errorCount = errorCount
            self.warningCount = warningCount
            self.indices = indices
        }
    }

    /// Partitions entries by mod, described only by what this needs to know:
    /// each entry's mod (nil = framework), whether it's an error, and whether
    /// it's a warning. Callers map their own log type onto that.
    ///
    /// Ordering puts the mods that need attention first (errors, then
    /// warnings), then the noisiest, then alphabetical — a player opening this
    /// view is usually looking for what broke, not for the busiest logger. The
    /// framework bucket always sorts last: it's context, not a mod to inspect.
    public static func groupByMod(
        count: Int,
        mod: (Int) -> String?,
        isError: (Int) -> Bool,
        isWarning: (Int) -> Bool
    ) -> [ModGroup] {
        var indices: [String: [Int]] = [:]
        var mods: [String: String?] = [:]
        for i in 0..<count {
            let name = mod(i)
            let key = name ?? "\u{0000}framework"
            indices[key, default: []].append(i)
            mods[key] = name
        }

        let groups = indices.map { key, idx -> ModGroup in
            ModGroup(
                mod: mods[key] ?? nil,
                lineCount: idx.count,
                errorCount: idx.reduce(0) { isError($1) ? $0 + 1 : $0 },
                warningCount: idx.reduce(0) { isWarning($1) ? $0 + 1 : $0 },
                indices: idx
            )
        }

        return groups.sorted { a, b in
            // Framework last.
            if (a.mod == nil) != (b.mod == nil) { return b.mod == nil }
            if a.errorCount != b.errorCount { return a.errorCount > b.errorCount }
            if a.warningCount != b.warningCount { return a.warningCount > b.warningCount }
            if a.lineCount != b.lineCount { return a.lineCount > b.lineCount }
            return (a.mod ?? "").localizedCaseInsensitiveCompare(b.mod ?? "") == .orderedAscending
        }
    }
}
