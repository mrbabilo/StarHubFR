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

    /// A mod with an associated count (e.g. ERROR lines attributed to it).
    public struct ModCount: Identifiable {
        public let id = UUID()
        public let name: String
        public let count: Int
        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    /// A known-harmless ERROR line, classified so the UI can reassure the
    /// player instead of alarming them. These never count as problems, and are
    /// excluded from `topErrorMods` so a healthy mod isn't blamed for them.
    public struct BenignNotice: Identifiable {
        public enum Kind: String {
            /// GOG Galaxy isn't signed in — affects the Galaxy overlay only.
            case galaxyAuth
            /// A mod's optional integration with another mod (typically its
            /// config menu) couldn't be wired up, usually a version mismatch.
            case apiIntegration
            /// An optional companion mod isn't installed; the mod says so and
            /// keeps working without it.
            case optionalModMissing
            /// A mod couldn't read part of its own content/config data. It's a
            /// mod-side bug: nothing for the player to fix.
            case modContentParse
        }
        public let id = UUID()
        public let kind: Kind
        /// The mod whose optional integration failed, when SMAPI names one.
        public let mod: String?
        /// How many times this mod hit this kind of notice.
        public var count: Int
        /// The first raw message seen, kept so the player can match the notice
        /// back to the actual log line instead of taking our word for it.
        public let sample: String

        public init(kind: Kind, mod: String?, count: Int = 1, sample: String = "") {
            self.kind = kind
            self.mod = mod
            self.count = count
            self.sample = sample
        }
    }

    /// A mod that requires a dependency which is not installed.
    public struct MissingDep: Identifiable {
        public let id = UUID()
        public let mod: String
        public let missing: String
        public init(mod: String, missing: String) {
            self.mod = mod
            self.missing = missing
        }
    }

    public var smapiVersion: String?
    public var gameVersion: String?
    public var modsLoaded: Int?
    public var contentPacksLoaded: Int?
    public var skipped: [Issue] = []
    public var failed: [Issue] = []
    public var externalConflicts: [String] = []
    /// Mods in SMAPI "warning group" sections. These are informational (normal
    /// for big modlists) and do NOT count toward `problemCount`.
    public var patchedMods: [String] = []
    public var saveSerializerMods: [String] = []
    public var brokenMods: [String] = []
    public var consoleMods: [String] = []
    /// Mods with a missing required dependency (promoted from failed/skipped).
    public var missingDeps: [MissingDep] = []
    /// Mods that logged the most ERROR lines (context attribution), top 5.
    public var topErrorMods: [ModCount] = []
    /// Known-harmless errors, explained to the player rather than hidden.
    public var benignNotices: [BenignNotice] = []

    public init() {}

    /// True when nothing useful was extracted (no version and no issues) — the
    /// UI hides the health card in that case.
    public var isEmpty: Bool {
        smapiVersion == nil
            && skipped.isEmpty && failed.isEmpty && externalConflicts.isEmpty
            && brokenMods.isEmpty && missingDeps.isEmpty && topErrorMods.isEmpty
            && patchedMods.isEmpty && saveSerializerMods.isEmpty && consoleMods.isEmpty
            && benignNotices.isEmpty
    }

    /// Issues to FIX (drive the card's healthy/unhealthy state). Only clear
    /// loadability problems: informational warning groups (patched /
    /// save-serializer / console), `missingDeps` (a subset of failed/skipped)
    /// and `topErrorMods` are shown as details but not double-counted here, so
    /// a normal large modlist doesn't make the card perpetually "unhealthy".
    public var problemCount: Int {
        skipped.count + failed.count + externalConflicts.count + brokenMods.count
    }

    /// Parse a raw SMAPI log. Tolerant by design: never throws, silently
    /// ignores lines it can't make sense of.
    public static func parse(logContent: String) -> SmapiDiagnostics {
        var d = SmapiDiagnostics()
        let lines = logContent.components(separatedBy: .newlines)

        var inSkipped = false
        var currentLoadingMod: String?
        var errorCounts: [String: Int] = [:]
        var group: WarningGroup? = nil
        var groupEntriesStarted = false

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
                    if let dep = missingDependency(in: issue.reason) {
                        d.missingDeps.append(.init(mod: issue.name, missing: dep))
                    }
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
                // Extract the missing dep from the RAW line body: failedIssue
                // reformulates the reason into "requires X (not installed)",
                // which moves the dep name out of the parentheses.
                if let mod = currentLoadingMod,
                   let dep = missingDependency(in: messageBody(of: raw)) {
                    d.missingDeps.append(.init(mod: mod, missing: dep))
                }
            }

            // External conflicts.
            if raw.contains("RivaTuner Statistics Server"),
               !d.externalConflicts.contains("RivaTuner Statistics Server") {
                d.externalConflicts.append("RivaTuner Statistics Server")
            }

            // Known-harmless errors: classify them (so the UI can reassure the
            // player) and keep them OUT of the per-mod error counts, otherwise
            // a perfectly working mod gets blamed for an optional integration
            // it can live without.
            let benign = benignNotice(inBody: messageBody(of: raw), line: raw)
            if let notice = benign {
                // Collapse repeats of the same (kind, mod) but keep the tally —
                // "3×" tells the player how noisy it was, and the first message
                // is kept as evidence they can look up in the raw log.
                if let i = d.benignNotices.firstIndex(where: { $0.kind == notice.kind && $0.mod == notice.mod }) {
                    d.benignNotices[i].count += 1
                } else {
                    d.benignNotices.append(notice)
                }
            }

            // Per-mod ERROR counts (context attribution; SMAPI/game excluded).
            if benign == nil, let mod = errorContextMod(of: raw) {
                errorCounts[mod, default: 0] += 1
            }

            // SMAPI warning-group sections (patched / save-serializer / broken /
            // console). Format: header `   {Heading}`, a 50-dash separator, a
            // blurb, a blank line, then `      - {Mod}` entries, a blank line.
            let groupBody = messageBody(of: raw).trimmingCharacters(in: .whitespaces)
            if group == nil {
                switch groupBody {
                case "Patched game code":       group = .patched; groupEntriesStarted = false
                case "Changed save serializer": group = .save;     groupEntriesStarted = false
                case "Broken mods":             group = .broken;   groupEntriesStarted = false
                case "Direct console access":   group = .console;  groupEntriesStarted = false
                default: break
                }
            } else if groupBody.allSatisfy({ $0 == "-" }) {
                continue // separator line — never capture as a mod
            } else if groupBody.isEmpty {
                if groupEntriesStarted { group = nil; groupEntriesStarted = false }
                // else: blank between blurb and entries — ignore
            } else if groupBody.hasPrefix("- ") {
                let name = groupBody.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    switch group {
                    case .patched: d.patchedMods.append(name)
                    case .save:    d.saveSerializerMods.append(name)
                    case .broken:  d.brokenMods.append(name)
                    case .console: d.consoleMods.append(name)
                    case .none:    break
                    }
                    groupEntriesStarted = true
                }
            } else if groupEntriesStarted {
                // Text after entries = next group header or unrelated line.
                group = nil; groupEntriesStarted = false
                switch groupBody {
                case "Patched game code":       group = .patched
                case "Changed save serializer": group = .save
                case "Broken mods":             group = .broken
                case "Direct console access":   group = .console
                default: break
                }
            }
            // (else: blurb text before entries — ignore)
        }

        // Top mods by ERROR count (top 5; count desc, then name asc).
        d.topErrorMods = errorCounts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(5)
            .map { ModCount(name: $0.key, count: $0.value) }

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

    // MARK: - Warning groups & per-mod errors

    /// Which SMAPI warning-group section is currently being parsed.
    private enum WarningGroup { case patched, save, broken, console }

    /// The mod context of a `[HH:MM:SS ERROR ModName] …` line, or nil for
    /// non-ERROR lines and framework contexts ("SMAPI", "game").
    private static func errorContextMod(of line: String) -> String? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let header = String(line[line.index(after: line.startIndex)..<close])
        let parts = header.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 3, parts[1].uppercased() == "ERROR" else { return nil }
        let name = parts[2...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != "SMAPI", name != "game" else { return nil }
        return name
    }

    /// Classifies known-harmless ERROR lines. Returns nil for anything else,
    /// so unknown errors keep their full weight.
    ///
    /// - Galaxy auth: GOG Galaxy isn't signed in; only the Galaxy overlay and
    ///   its achievements are affected, the game and mods run fine.
    /// - API integration: a mod tried to use another mod's optional API
    ///   (typically Generic Mod Config Menu) and the interfaces didn't match,
    ///   usually a version gap. The mod itself still loads and works; only that
    ///   integration (e.g. its in-game settings page) is unavailable.
    private static func benignNotice(inBody body: String, line: String) -> BenignNotice? {
        let low = body.lowercased()

        // A mod that says its own warning is ignorable is taken at its word —
        // this generalizes to any mod using that phrasing, not a hardcoded list.
        if low.contains("you can ignore this warning")
            || low.contains("you can safely ignore")
            || low.contains("this is not an error") {
            return BenignNotice(kind: .apiIntegration,
                                mod: modPrefix(of: body, before: ":"),
                                sample: evidence(from: body))
        }

        for rule in benignRules where rule.matches(low) {
            let mod = rule.namesMod
                ? (modPrefix(of: body, before: ":") ?? errorContextMod(of: line))
                : nil
            return BenignNotice(kind: rule.kind, mod: mod, sample: evidence(from: body))
        }
        return nil
    }

    /// A one-line excerpt of the original message, kept as the notice's
    /// evidence. Stack traces and multi-line details are cut to the first line
    /// so the card stays readable.
    private static func evidence(from body: String) -> String {
        let firstLine = body
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? body
        let limit = 160
        guard firstLine.count > limit else { return firstLine }
        return String(firstLine.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A known-harmless log signature. Adding a case is a table entry, not code:
    /// `any` matches if ANY substring is present, `all` requires every one.
    /// Matching is case-insensitive (patterns must be lowercase).
    private struct BenignRule {
        let kind: BenignNotice.Kind
        var any: [String] = []
        var all: [String] = []
        /// Whether the message is prefixed with the mod name ("<Mod>: …").
        var namesMod = true

        func matches(_ lowercasedBody: String) -> Bool {
            if !all.isEmpty, !all.allSatisfy(lowercasedBody.contains) { return false }
            if !any.isEmpty, !any.contains(where: lowercasedBody.contains) { return false }
            return !(any.isEmpty && all.isEmpty)
        }
    }

    /// Generalized signatures of harmless log lines. Each covers a *family* of
    /// messages rather than one mod's exact wording.
    private static let benignRules: [BenignRule] = [
        // Platform sign-in (GOG Galaxy / Steam): overlay + achievements only.
        .init(kind: .galaxyAuth,
              any: ["galaxy auth failure", "galaxy_service_not_signed_in", "not signed in to steam"],
              namesMod: false),

        // Optional integration with another mod's API couldn't be wired up:
        // interface mismatch, missing API, or the other mod being absent.
        .init(kind: .apiIntegration,
              any: ["tried to map a mod-provided api",
                    "isn't compatible with the actual mod api",
                    "couldn't get the",          // "Couldn't get the X API"
                    "could not get the",
                    "failed to get the",
                    "api not found",
                    "integration failed",
                    "unable to load api"]),

        // An optional/recommended companion mod isn't installed.
        .init(kind: .optionalModMissing,
              any: ["recommended mod not installed",
                    "optional mod not installed",
                    "optional dependency",
                    "is not installed, skipping integration",
                    "not installed - skipping"]),

        // A mod couldn't read part of its own content/config data.
        .init(kind: .modContentParse,
              any: ["failed to parse condition",
                    "failed to parse integer",
                    "failed to parse boolean",
                    "failed to parse field",
                    "bad value:",
                    "couldn't parse",
                    "invalid value for"])
    ]

    /// The mod name written before `marker` in a message body
    /// (`"<Mod Name>: <message>"`), or nil when the body doesn't start that way.
    /// Guards against sentence-like prefixes so a stray colon isn't read as a
    /// mod name.
    private static func modPrefix(of body: String, before marker: String) -> String? {
        guard let range = body.range(of: marker) else { return nil }
        let name = body[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 60, !name.contains(" - ") else { return nil }
        return name
    }

    /// Extracts a missing-dependency name from a reason that mentions
    /// "not installed" (failed, reformulated) or "aren't installed" (skipped,
    /// raw), reading the parenthesized list. Nil otherwise.
    private static func missingDependency(in reason: String) -> String? {
        let low = reason.lowercased()
        guard low.contains("not installed") || low.contains("aren't installed") else { return nil }
        return parenContent(of: reason)
    }
}
