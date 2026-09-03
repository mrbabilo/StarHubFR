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

        // SMAPI écrit le nom du mod **sans guillemets** dans ses lignes de rejet
        // (« Skipped Foo (folder name starts with a dot) »), si bien que chaque
        // ligne avait une signature unique et qu'aucune ne se repliait — une
        // recherche du mod responsable en produit des centaines. On masque le
        // nom pour ne garder que la raison, qui est la vraie famille.
        s = replacing(s, pattern: "(?i)^(Skipped|Removed|Ignored) .+?( \\(| because )",
                      with: "$1 ~$2")

        // Long messages can still differ far to the right; the head carries the
        // shape, so cap it to keep signatures cheap to compare.
        return String(s.prefix(120))
    }

    /// Nom de mod porté en préfixe d'un message SMAPI (« Nom du mod: … »).
    ///
    /// SMAPI écrit certaines erreurs **pour le compte** d'un mod : le crochet de
    /// source porte « SMAPI » et le nom n'apparaît qu'en tête du message —
    /// « [SMAPI] [ERROR] Gunther's Guide: Tried to map… ». Sans cette lecture,
    /// ces erreurs n'étaient imputées à personne : ni dans l'historique par mod,
    /// ni dans le relevé de la recherche guidée.
    ///
    /// L'appelant filtre sur le niveau ; ici on écarte ce qui ne peut pas être
    /// un nom de mod, pour qu'une ligne anodine contenant un deux-points
    /// n'invente pas un coupable.
    ///
    /// ⚠️ **C'est une heuristique sur du texte libre, et aucun critère
    /// textuel ne la rend sûre.** Relevé sur le journal de l'auteur
    /// (2026-09-01, 4 638 entrées) : elle se déclenche **3 fois** et se trompe
    /// **3 fois** — `You can update 1 mod`, `Galaxy auth failure`, et
    /// `Mod Update Menu 2.7.0` (un vrai nom de mod, mais suivi de sa version,
    /// donc irrésoluble). Le cas pour lequel elle existe —
    /// `Gunther's Guide: Tried to map…`, une erreur que SMAPI journalise pour
    /// le compte d'un mod sous son propre crochet — **ne figure pas dans ce
    /// journal-là** : 3 sur 3 ne dit pas que l'heuristique est inutile, il dit
    /// que ce journal ne contenait que ses faux positifs.
    ///
    /// Les consommateurs ne la traitent **pas** de la même façon, et c'est le
    /// point à connaître :
    /// - `StarHubTHViewModel.recordErrorHistory` passe chaque imputation par
    ///   `resolveModFolder(forLoggedName:)` — rien de fantôme n'est donc
    ///   **persisté** dans l'historique par mod ;
    /// - `LogsView` lui fait confiance telle quelle : la pastille cliquable
    ///   (`:650`) et le regroupement par mod (`:102`) affichent ces trois noms
    ///   comme des mods, et la pastille ne mène nulle part.
    ///
    /// Le correctif évident — ne montrer que les noms qui résolvent — ne peut
    /// **pas** vivre ici : `SmapiLogParser.parse` tourne sur
    /// `DispatchQueue.global` (`loadSmapiLog`), où la liste des mods
    /// (`@Published`, isolée sur le fil principal) n'est pas lisible. La
    /// validation ne peut se faire que côté consommation.
    public static func modNamePrefix(in message: String) -> String? {
        guard let colon = message.firstIndex(of: ":") else { return nil }
        let candidate = String(message[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty, candidate.count <= 60,
              !candidate.contains(where: { $0.isNewline }),  // multi-ligne (CRLF = 1 Character)
              !candidate.contains("/"), !candidate.contains("\\"),  // chemin ou URL
              !candidate.contains(". "),                            // phrase
              candidate.rangeOfCharacter(from: .letters) != nil else { return nil }
        return candidate
    }

    private static func replacing(_ string: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let range = NSRange(location: 0, length: (string as NSString).length)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }

    // MARK: - Locating a warning-group section

    /// Finds the span of a SMAPI warning-group section in a list of log
    /// messages, so the UI can show the block that lists the affected mods
    /// exactly as SMAPI wrote it.
    ///
    /// SMAPI's format is a header line, a 50-dash separator, a blurb, then one
    /// `- ModName` line per mod. The block ends at the first ordinary line after
    /// those entries. Returns the range covering header through last entry, or
    /// nil when the header isn't present.
    public static func warningGroupRange(messages: [String], header: String) -> Range<Int>? {
        let target = header.trimmingCharacters(in: .whitespaces)
        guard let start = messages.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == target
        }) else { return nil }

        var end = start + 1
        var lastEntry = start
        var entriesStarted = false

        while end < messages.count {
            let line = messages[end].trimmingCharacters(in: .whitespaces)

            if !line.isEmpty && line.allSatisfy({ $0 == "-" }) {
                end += 1                      // separator
                continue
            }
            if line.hasPrefix("- ") {
                entriesStarted = true
                lastEntry = end
                end += 1
                continue
            }
            if line.isEmpty {
                if entriesStarted { break }   // blank after entries closes it
                end += 1                      // blank between blurb and entries
                continue
            }
            if entriesStarted { break }       // next section's header
            end += 1                          // blurb text
        }

        return start..<(lastEntry + 1)
    }

    // MARK: - Trimming to a cap

    /// Selects which entries to keep when a log exceeds `cap`, by sacrificing
    /// low-signal lines instead of cutting the start of the file.
    ///
    /// Returns the indices to keep, in original order.
    ///
    /// SMAPI writes its diagnostic (skipped mods, save-serializer warnings,
    /// failed integrations) at startup, so a naive "keep the last N" drops
    /// precisely the lines a player needs — and makes the log list disagree
    /// with the diagnostics card, which reads the whole file. Signal lines
    /// (anything that isn't TRACE) are kept from the start; the remaining room
    /// goes to the most recent noise, so late TRACE context survives too.
    public static func trimIndices(count: Int, cap: Int, isNoise: (Int) -> Bool) -> [Int] {
        guard count > cap else { return Array(0..<count) }

        var signal: [Int] = []
        var noise: [Int] = []
        for i in 0..<count {
            if isNoise(i) { noise.append(i) } else { signal.append(i) }
        }

        // Signal alone can overflow the cap: keep the earliest lines, where
        // SMAPI's startup diagnostic lives.
        if signal.count >= cap { return Array(signal.prefix(cap)) }

        let room = cap - signal.count
        let keptNoise = Set(noise.suffix(room))
        return (0..<count).filter { !isNoise($0) || keptNoise.contains($0) }
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
