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
}
