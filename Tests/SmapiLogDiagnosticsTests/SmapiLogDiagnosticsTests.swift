import Testing
@testable import StarHubTHCore

/// Tests for `SmapiDiagnostics.parse` — patterns drawn from a real
/// `SMAPI-latest.txt` (header, counts, "Skipped mods" block with reasons,
/// "(from Mods/…)" attribution, "Failed:" lines, external conflicts).
@Suite struct SmapiLogDiagnosticsTests {

    /// A representative SMAPI log excerpt covering every parsed field.
    private static let sample = """
    [22:29:43 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 build 24356 on macOS Unix 26.5.2
    [22:29:43 INFO  SMAPI] Mods go here: /Applications/Stardew Valley.app/Contents/MacOS/Mods
    [22:29:54 TRACE SMAPI]    Generic Mod Config Menu (from Mods/GenericModConfigMenu/GenericModConfigMenu.dll, ID: spacechase0.GenericModConfigMenu, assembly version: 1.16.0)...
    [22:30:00 INFO  SMAPI] Loaded 64 mods:
    [22:30:00 INFO  SMAPI] Loaded 19 content packs:
    [22:30:00 ERROR SMAPI]    Skipped mods
    [22:30:00 ERROR SMAPI]       - AutoForager 0.5.3 because its DLL couldn't be loaded: Could not load file. Do you have two copies of this mod?
    [22:30:00 ERROR SMAPI]       - AnotherMod 1.0 because it requires mods which aren't installed (Some.Library)
    [22:30:00 ERROR SMAPI]    These mods could not be added because they won't load.
    [22:31:00 TRACE SMAPI]    Bad Mod (from Mods/BadMod/BadMod.dll, ID: bad.mod, assembly version: 1.0.0)...
    [22:31:01 ERROR Bad Mod] Failed: something went wrong initializing
    [22:31:02 WARN  Game] RivaTuner Statistics Server detected; this may cause issues
    """

    @Test func parsesVersionsAndCounts() {
        let d = SmapiDiagnostics.parse(logContent: Self.sample)
        #expect(d.smapiVersion == "4.5.2")
        #expect(d.gameVersion == "1.6.15")
        #expect(d.modsLoaded == 64)
        #expect(d.contentPacksLoaded == 19)
    }

    @Test func parsesSkippedModsWithReasons() {
        let d = SmapiDiagnostics.parse(logContent: Self.sample)
        #expect(d.skipped.count == 2, "Skipped section must stop at the trailing summary line")
        let names = d.skipped.map(\.name)
        #expect(names.contains("AutoForager 0.5.3"))
        // The reason is captured verbatim (missing-dep extraction is for Failed).
        let another = d.skipped.first { $0.name == "AnotherMod 1.0" }
        #expect(another?.reason.contains("Some.Library") == true)
        let forager = d.skipped.first { $0.name.hasPrefix("AutoForager") }
        #expect(forager?.reason.contains("DLL couldn't be loaded") == true)
    }

    @Test func attributesFailedToLoadingMod() {
        let d = SmapiDiagnostics.parse(logContent: Self.sample)
        #expect(d.failed.count == 1)
        #expect(d.failed.first?.name == "Bad Mod", "Failed: must be attributed to the last '(from Mods/…)' mod")
        #expect(d.failed.first?.reason.contains("something went wrong") == true)
    }

    @Test func detectsExternalConflict() {
        let d = SmapiDiagnostics.parse(logContent: Self.sample)
        #expect(d.externalConflicts == ["RivaTuner Statistics Server"])
    }

    @Test func problemCountSumsIssues() {
        let d = SmapiDiagnostics.parse(logContent: Self.sample)
        // 2 skipped + 1 failed + 1 conflict
        #expect(d.problemCount == 4)
    }

    @Test func emptyLogYieldsEmptyDiagnostics() {
        let d = SmapiDiagnostics.parse(logContent: "not a smapi log\nno diagnostics here")
        #expect(d.isEmpty)
        #expect(d.problemCount == 0)
    }

    @Test func missingDependencyIsSurfacedPlainlyInFailedReason() {
        // A Failed: line that names a missing dependency should surface the dep.
        let log = """
        [00:00:00 TRACE SMAPI]    NEU Mod (from Mods/NEU/NEU.dll, ID: neu.mod)...
        [00:00:01 ERROR NEU Mod] Failed: requires mods which aren't installed (Some.Framework)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.failed.count == 1)
        #expect(d.failed.first?.reason == "requires Some.Framework (not installed)")
    }

    @Test func parsesPatchedGameCodeGroupAndSkipsSeparator() {
        let log = """
        [22:30:00 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15
        [22:30:00 INFO  SMAPI]    Patched game code
        [22:30:00 INFO  SMAPI]    --------------------------------------------------
        [22:30:00 INFO  SMAPI]       These mods directly change the game code. They're more likely to cause errors or bugs in-game; if
        [22:30:00 INFO  SMAPI]       your game has issues, try removing these first. Otherwise you can ignore this warning.

        [22:30:00 INFO  SMAPI]       - Content Patcher
        [22:30:00 INFO  SMAPI]       - Stardew Valley Expanded

        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.patchedMods == ["Content Patcher", "Stardew Valley Expanded"])
        // The 50-dash separator line must never be captured as a mod.
        #expect(d.patchedMods.allSatisfy { !$0.allSatisfy { $0 == "-" } })
    }

    @Test func parsesMultipleWarningGroups() {
        let log = """
        [22:30:00 WARN  SMAPI]    Changed save serializer
        [22:30:00 WARN  SMAPI]    --------------------------------------------------
        [22:30:00 WARN  SMAPI]       These mods change the save serializer.

        [22:30:00 WARN  SMAPI]       - Save Serializer Mod

        [22:30:00 ERROR SMAPI]    Broken mods
        [22:30:00 ERROR SMAPI]    --------------------------------------------------
        [22:30:00 ERROR SMAPI]       These mods have broken code.

        [22:30:00 ERROR SMAPI]       - Broken Mod One
        [22:30:00 ERROR SMAPI]       - Broken Mod Two

        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.saveSerializerMods == ["Save Serializer Mod"])
        #expect(d.brokenMods == ["Broken Mod One", "Broken Mod Two"])
    }

    @Test func promotesMissingDependenciesFromFailedAndSkipped() {
        let log = """
        [00:00:00 TRACE SMAPI]    NEU Mod (from Mods/NEU/NEU.dll, ID: neu.mod)...
        [00:00:01 ERROR NEU Mod] Failed: requires mods which aren't installed (Some.Framework)
        [00:00:02 ERROR SMAPI]    Skipped mods
        [00:00:02 ERROR SMAPI]       - AnotherMod 1.0 because it requires mods which aren't installed (Some.Library)
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.missingDeps.count == 2)
        #expect(d.missingDeps.first { $0.mod == "NEU Mod" }?.missing == "Some.Framework")
        #expect(d.missingDeps.first { $0.mod == "AnotherMod 1.0" }?.missing == "Some.Library")
    }

    @Test func countsPerModErrorsTop5ExcludingFramework() {
        let log = """
        [12:00:00 ERROR Content Patcher] foo
        [12:00:01 ERROR game] bar
        [12:00:02 ERROR Content Patcher] baz
        [12:00:03 ERROR SMAPI] qux
        [12:00:04 ERROR Another Mod] quux
        [12:00:05 WARN Content Patcher] not-counted
        """
        let d = SmapiDiagnostics.parse(logContent: log)
        #expect(d.topErrorMods.first?.name == "Content Patcher")
        #expect(d.topErrorMods.first?.count == 2)
        #expect(d.topErrorMods.count == 2)
        let names = d.topErrorMods.map(\.name)
        #expect(!names.contains("game") && !names.contains("SMAPI"))
    }
}
