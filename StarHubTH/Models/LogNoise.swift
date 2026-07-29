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
}
