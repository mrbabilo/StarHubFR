import Foundation

/// Structured diagnostics extracted from a SMAPI log (`SMAPI-latest.txt`).
///
/// Pure parser (no I/O) so it is unit-testable in the Core target. The
/// ViewModel reads the file and feeds its contents to `parse(logContent:)`.
/// Mirrors the diagnostics surfaced by ZeroXPatch/`SMAPILogDoctor.py`: SMAPI /
/// game versions, loaded mod / content-pack counts, skipped mods (with
/// reasons), failed mods (with reasons, including missing dependencies), and
/// known external conflicts (e.g. RivaTuner Statistics Server).
///
/// Update alerts are intentionally NOT captured here — the existing
/// `outOfDateMods` pipeline (Updates tab) already covers them, so this type
/// stays focused on health/loadability diagnostics.
public struct SmapiDiagnostics {
    /// A named diagnostic item with a human-readable reason (skipped mod,
    /// failed load, …). `Identifiable` so it can drive a SwiftUI `ForEach`.
    public struct Issue: Identifiable {
        public let id = UUID()
        public let name: String
        public let reason: String
        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public var smapiVersion: String?
    public var gameVersion: String?
    public var modsLoaded: Int?
    public var contentPacksLoaded: Int?
    public var skipped: [Issue] = []
    public var failed: [Issue] = []
    public var externalConflicts: [String] = []

    public init() {}

    /// True when nothing useful was extracted (no version and no issues) — the
    /// UI hides the health card in that case.
    public var isEmpty: Bool {
        smapiVersion == nil && skipped.isEmpty && failed.isEmpty && externalConflicts.isEmpty
    }

    public var problemCount: Int {
        skipped.count + failed.count + externalConflicts.count
    }

    /// Parse a raw SMAPI log. Tolerant by design: never throws, silently
    /// ignores lines it can't make sense of.
    public static func parse(logContent: String) -> SmapiDiagnostics {
        var d = SmapiDiagnostics()
        let lines = logContent.components(separatedBy: .newlines)

        var inSkipped = false
        var currentLoadingMod: String?

        for raw in lines {
            // Versions (first match wins — the SMAPI header line).
            if d.smapiVersion == nil,
               let g = matches(in: raw, pattern: #"SMAPI\s+([0-9][0-9.]*)\s+with Stardew Valley\s+([0-9][0-9.]*)"#) {
                d.smapiVersion = g[0]
                d.gameVersion = g[1]
            }

            // Loading attribution: "] <Mod Name> (from Mods/...)" — track the
            // last mod being loaded so a subsequent "Failed:" can be attributed.
            if raw.contains("(from Mods/") {
                currentLoadingMod = modName(fromLoadingLine: raw)
            }

            // Counts.
            if d.modsLoaded == nil,
               let n = firstInt(in: raw, pattern: #"Loaded\s+(\d+)\s+mods:"#) {
                d.modsLoaded = n
            }
            if d.contentPacksLoaded == nil,
               let n = firstInt(in: raw, pattern: #"Loaded\s+(\d+)\s+content packs:"#) {
                d.contentPacksLoaded = n
            }

            // Skipped-mods section (multi-line block).
            if raw.contains("Skipped mods") {
                inSkipped = true
                continue
            }
            if inSkipped {
                if let issue = skippedIssue(fromLine: raw) {
                    d.skipped.append(issue)
                    continue
                }
                // Exit the block on a non-empty line that isn't an entry.
                let body = messageBody(of: raw)
                if !body.isEmpty && !body.hasPrefix("-") {
                    inSkipped = false
                }
            }

            // Failed loads.
            if let issue = failedIssue(fromLine: raw, currentMod: currentLoadingMod) {
                d.failed.append(issue)
            }

            // External conflicts.
            if raw.contains("RivaTuner Statistics Server"),
               !d.externalConflicts.contains("RivaTuner Statistics Server") {
                d.externalConflicts.append("RivaTuner Statistics Server")
            }
        }
        return d
    }

    // MARK: - Line helpers

    /// Capture groups (0-indexed = first group) of the first regex match, or nil.
    private static func matches(in string: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = string as NSString
        guard let m = regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            groups.append(ns.substring(with: m.range(at: i)))
        }
        return groups
    }

    private static func firstInt(in string: String, pattern: String) -> Int? {
        guard let g = matches(in: string, pattern: pattern), let first = g.first, let n = Int(first) else { return nil }
        return n
    }

    /// Everything after the first `]` (trimmed) when the line is bracketed,
    /// else the trimmed line. SMAPI lines look like
    /// `[HH:MM:SS LEVEL  Context] message body…`.
    private static func messageBody(of line: String) -> String {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
    }

    /// Skipped entry: body starts with `-` and contains ` because `.
    /// `<name> <version> because <reason>` → Issue(name, reason).
    private static func skippedIssue(fromLine line: String) -> Issue? {
        let body = messageBody(of: line)
        guard body.hasPrefix("-") else { return nil }
        let content = body.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let because = content.range(of: " because ", options: .caseInsensitive) else { return nil }
        let name = content[..<because.lowerBound].trimmingCharacters(in: .whitespaces)
        let reason = content[because.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return Issue(name: name, reason: reason)
    }

    /// Failed entry: body mentions `Failed:`. Attributed to `currentMod` when
    /// known. If SMAPI names a missing dependency, surface it plainly.
    private static func failedIssue(fromLine line: String, currentMod: String?) -> Issue? {
        let body = messageBody(of: line)
        guard let r = body.range(of: "Failed:", options: .caseInsensitive) else { return nil }
        var reason = body[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if reason.contains("aren't installed"), let dep = parenContent(of: reason) {
            reason = "requires \(dep) (not installed)"
        }
        guard !reason.isEmpty else { return nil }
        return Issue(name: currentMod ?? "SMAPI", reason: reason)
    }

    /// Mod name from a loading line: the text before `(from Mods/`.
    private static func modName(fromLoadingLine line: String) -> String? {
        let body = messageBody(of: line)
        guard let from = body.range(of: "(from Mods/") else { return nil }
        let before = body[..<from.lowerBound].trimmingCharacters(in: .whitespaces)
        return before.isEmpty ? nil : before
    }

    private static func parenContent(of string: String) -> String? {
        guard let open = string.firstIndex(of: "("),
              let close = string.lastIndex(of: ")"),
              open < close else { return nil }
        return String(string[string.index(after: open)..<close])
    }
}
