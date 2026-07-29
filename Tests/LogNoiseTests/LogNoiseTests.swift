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
}
