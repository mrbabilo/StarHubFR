import Testing
@testable import StarHubTHCore

/// Signatures drawn from a real 4038-line SMAPI log where 3626 lines were TRACE,
/// dominated by a few message shapes with a varying asset name.
@Suite struct LogNoiseTests {

    @Test func sameShapeWithDifferentQuotedNamesSharesSignature() {
        let a = "Content Patcher loaded asset 'Maps/springobjects' (for the 'Lost Library' content pack)."
        let b = "Content Patcher loaded asset 'Data/Objects' (for the 'Ridgeside Village' content pack)."
        #expect(LogNoise.signature(of: a) == LogNoise.signature(of: b))
    }

    @Test func differentShapesDoNotShareSignature() {
        let loaded = "Loaded 'AutoForager.dll'"
        let invalidated = "Invalidated 12 cache entries."
        #expect(LogNoise.signature(of: loaded) != LogNoise.signature(of: invalidated))
    }

    @Test func numbersAreMaskedSoCountsCollapse() {
        #expect(LogNoise.signature(of: "Invalidated 0 cache entries.")
                == LogNoise.signature(of: "Invalidated 39 cache entries."))
    }

    /// A quoted name containing digits must not land in a different family from
    /// one without — quoted spans are masked before digits for this reason.
    @Test func quotedNamesWithDigitsShareSignatureWithPlainOnes() {
        #expect(LogNoise.signature(of: "Requested cache invalidation for 'Data/Powers'.")
                == LogNoise.signature(of: "Requested cache invalidation for 'Mod2/dictionary3'."))
    }

    @Test func onlyFirstLineCountsSoStackTracesDontFragmentFamilies() {
        let a = "Failed to load\n   at Foo.Bar()\n   at Baz.Qux()"
        let b = "Failed to load\n   at Different.Frame()"
        #expect(LogNoise.signature(of: a) == LogNoise.signature(of: b))
    }

    @Test func signatureIgnoresSurroundingWhitespace() {
        #expect(LogNoise.signature(of: "   Loaded 'X'   ") == LogNoise.signature(of: "Loaded 'X'"))
    }

    // MARK: - Locating a warning-group section

    /// Shaped like SMAPI's real output: header, 50-dash separator, blurb, blank,
    /// entries, blank, then the next section.
    private static let groupMessages = [
        "Loaded 64 mods:",
        "Changed save serializer",
        String(repeating: "-", count: 50),
        "These mods change the save serializer. They may corrupt your save files,",
        "or make them unusable if you uninstall these mods.",
        "",
        "- SpaceCore",
        "- Another Serializer Mod",
        "",
        "Patched game code",
        String(repeating: "-", count: 50),
        "These mods directly change the game code.",
        "",
        "- Content Patcher",
        ""
    ]

    @Test func findsWarningGroupSpanFromHeaderThroughLastEntry() {
        let range = LogNoise.warningGroupRange(messages: Self.groupMessages,
                                               header: "Changed save serializer")
        #expect(range == 1..<8, "Header through the last '- Mod' entry")
        let block = range.map { Array(Self.groupMessages[$0]) } ?? []
        #expect(block.first == "Changed save serializer")
        #expect(block.last == "- Another Serializer Mod")
        #expect(block.contains("- SpaceCore"))
    }

    /// The block must stop before the next section, not swallow it.
    @Test func warningGroupStopsBeforeTheNextSection() {
        let range = LogNoise.warningGroupRange(messages: Self.groupMessages,
                                               header: "Changed save serializer")
        let block = range.map { Array(Self.groupMessages[$0]) } ?? []
        #expect(!block.contains("Patched game code"))
        #expect(!block.contains("- Content Patcher"))
    }

    @Test func findsASectionThatRunsToTheEndOfTheLog() {
        let range = LogNoise.warningGroupRange(messages: Self.groupMessages,
                                               header: "Patched game code")
        let block = range.map { Array(Self.groupMessages[$0]) } ?? []
        #expect(block.first == "Patched game code")
        #expect(block.last == "- Content Patcher")
    }

    @Test func returnsNilWhenTheSectionIsAbsent() {
        #expect(LogNoise.warningGroupRange(messages: Self.groupMessages,
                                           header: "Direct console access") == nil)
    }

    // MARK: - Trimming to a cap

    /// The real bug: a 4038-line log capped at 2000 used to keep the *last*
    /// 2000, dropping 174 WARN/ERROR/INFO lines that SMAPI writes at startup.
    /// They stayed in the diagnostics card (full-file parse) but disappeared
    /// from the log list.
    @Test func trimKeepsEarlySignalAndDropsNoise() {
        // Index 0 = a startup WARN, then 4000 TRACE lines.
        let count = 4001
        let isNoise: (Int) -> Bool = { $0 != 0 }
        let keep = LogNoise.trimIndices(count: count, cap: 2000, isNoise: isNoise)
        #expect(keep.count == 2000)
        #expect(keep.first == 0, "The startup warning must survive the trim")
        #expect(keep.last == count - 1, "Recent noise fills the remaining room")
    }

    @Test func trimReturnsEverythingBelowCap() {
        let keep = LogNoise.trimIndices(count: 10, cap: 2000, isNoise: { _ in true })
        #expect(keep == Array(0..<10))
    }

    @Test func trimKeepsOrderAndRespectsCapWhenSignalOverflows() {
        // More signal than the cap: keep the earliest, still in order.
        let keep = LogNoise.trimIndices(count: 3000, cap: 100, isNoise: { _ in false })
        #expect(keep.count == 100)
        #expect(keep == Array(0..<100), "Earliest signal wins, order preserved")
    }

    @Test func trimmedIndicesStayInOriginalOrder() {
        // Alternating signal/noise, cap forces some noise to be dropped.
        let keep = LogNoise.trimIndices(count: 100, cap: 60, isNoise: { $0 % 2 == 1 })
        #expect(keep == keep.sorted(), "Indices must stay in original order")
        #expect(keep.count == 60)
        // All 50 signal lines survive.
        #expect(keep.filter { $0 % 2 == 0 }.count == 50)
    }

    // MARK: - Grouping by mod

    /// (mod, isError, isWarning) triples standing in for log entries.
    private static let sample: [(String?, Bool, Bool)] = [
        (nil, false, false),            // framework
        (nil, true,  false),            // framework error
        ("Quiet Mod", false, false),
        ("Noisy Mod", false, false),
        ("Noisy Mod", false, false),
        ("Noisy Mod", false, false),
        ("Broken Mod", true, false),
        ("Warned Mod", false, true)
    ]

    private static func group() -> [LogNoise.ModGroup] {
        LogNoise.groupByMod(
            count: sample.count,
            mod: { sample[$0].0 },
            isError: { sample[$0].1 },
            isWarning: { sample[$0].2 }
        )
    }

    @Test func groupsByModWithCountsAndIndices() {
        let groups = Self.group()
        let noisy = groups.first { $0.mod == "Noisy Mod" }
        #expect(noisy?.lineCount == 3)
        #expect(noisy?.indices == [3, 4, 5], "Indices keep their original order")
        #expect(groups.first { $0.mod == "Broken Mod" }?.errorCount == 1)
        #expect(groups.first { $0.mod == "Warned Mod" }?.warningCount == 1)
    }

    @Test func ordersProblemsFirstThenNoisiestThenAlphabetical() {
        let mods = Self.group().map { $0.mod }
        #expect(mods.first == "Broken Mod", "Errors come first")
        #expect(mods[1] == "Warned Mod", "Then warnings")
        #expect(mods[2] == "Noisy Mod", "Then the noisiest")
        #expect(mods[3] == "Quiet Mod")
    }

    /// Two thirds of a real log is SMAPI/game output, errors included — it must
    /// stay reachable, just out of the way.
    @Test func frameworkBucketIsKeptAndSortsLast() {
        let groups = Self.group()
        let framework = groups.last
        #expect(framework?.mod == nil, "Framework sorts last despite its error")
        #expect(framework?.lineCount == 2)
        #expect(framework?.errorCount == 1)
    }

    @Test func hasProblemsFlagsErrorsAndWarningsOnly() {
        let groups = Self.group()
        #expect(groups.first { $0.mod == "Broken Mod" }?.hasProblems == true)
        #expect(groups.first { $0.mod == "Warned Mod" }?.hasProblems == true)
        #expect(groups.first { $0.mod == "Quiet Mod" }?.hasProblems == false)
    }

    @Test func groupingEmptyInputYieldsNoGroups() {
        let groups = LogNoise.groupByMod(count: 0, mod: { _ in nil },
                                         isError: { _ in false }, isWarning: { _ in false })
        #expect(groups.isEmpty)
    }

    @Test func skippedModsFoldIntoOneFamilyPerReason() {
        // SMAPI nomme le mod sans guillemets, donc rien ne se repliait : une
        // recherche du mod responsable met des dizaines de dossiers en pause et
        // remplissait le journal d'une ligne par mod.
        let a = LogNoise.signature(of: "Skipped Gunther's Guide (folder name starts with a dot)")
        let b = LogNoise.signature(of: "Skipped Let's Move It (folder name starts with a dot)")
        #expect(a == b)

        // Deux raisons différentes restent deux familles.
        let c = LogNoise.signature(of: "Skipped Foo because it requires mods which aren't installed")
        #expect(a != c)

        // Une ligne ordinaire n'est pas affectée.
        let d = LogNoise.signature(of: "Invalidated 3 cache entries.")
        #expect(d != a)
    }
}
