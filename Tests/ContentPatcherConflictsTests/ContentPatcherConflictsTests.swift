import Testing
import Foundation
@testable import StarHubTHCore

/// Les messages sont reconstitués depuis l'IL de `ContentPatcher.dll`
/// (`ikdasm`, 2026-08-29) : la séquence `AppendLiteral` / `AppendFormatted` donne
/// l'ordre exact des littéraux et des valeurs.
struct ContentPatcherConflictsTests {

    private func entry(_ message: String, level: LogLevel = .error,
                       mod: String? = "Content Patcher") -> LogEntry {
        LogEntry(timestamp: "15:55:06", message: message, level: level,
                 source: .smapi, modName: mod)
    }

    @Test func twoPacksFightingOverOneAsset() throws {
        let found = ContentPatcherConflicts.read(from: [entry(
            "Two content packs want to load the 'Portraits/Haley' asset with the 'Exclusive' priority ([CP] Aelinore and [CP] Miihaus). Neither will be applied. You should remove one of them.")])
        #expect(found.count == 1)
        #expect(found.first?.asset == "Portraits/Haley")
        #expect(found.first?.packs == ["[CP] Aelinore", "[CP] Miihaus"])
        #expect(found.first?.kind == .betweenPacks)
    }

    @Test func threePacksOrMore() throws {
        let found = ContentPatcherConflicts.read(from: [entry(
            "Multiple content packs want to load the 'Animals/Dog' asset with the 'Exclusive' priority ([CP] FOTP, [CP] Pet Facelift, Pets Enhanced). None will be applied. You should remove some of them.")])
        #expect(found.count == 1)
        #expect(found.first?.packs == ["[CP] FOTP", "[CP] Pet Facelift", "Pets Enhanced"])
        #expect(found.first?.kind == .betweenPacks)
    }

    /// **Un mod contre lui-même**, ce qui n'est pas une paire : c'est à signaler
    /// à son auteur, pas à arbitrer par l'utilisateur.
    @Test func aPackFightingWithItself() throws {
        let found = ContentPatcherConflicts.read(from: [entry(
            "'[CP] Nyapu' has multiple patches with the 'Exclusive' priority which load the 'Portraits/Abigail' asset at the same time (EntryA, EntryB). None will be applied. You should report this to the mod author.")])
        #expect(found.first?.kind == .withinOnePack)
        #expect(found.first?.packs == ["[CP] Nyapu"])
        #expect(found.first?.asset == "Portraits/Abigail")
    }

    /// **L'ancrage tient quand le conseil final change.** C'est la partie du
    /// message qui bougera d'une version de Content Patcher à l'autre ; le
    /// parseur ne doit pas s'y accrocher.
    @Test func theTrailingAdviceIsNotAnAnchor() throws {
        let found = ContentPatcherConflicts.read(from: [entry(
            "Two content packs want to load the 'Maps/Town' asset with the 'Exclusive' priority (A and B). Nothing at all will happen, sorry.")])
        #expect(found.first?.packs == ["A", "B"])
    }

    @Test func linesFromOtherModsAndOtherLevelsAreIgnored() throws {
        let noise = [
            entry("Two content packs want to load the 'X' asset with the 'Exclusive' priority (A and B).",
                  level: .trace),
            entry("Two content packs want to load the 'X' asset with the 'Exclusive' priority (A and B).",
                  mod: "Generic Mod Config Menu"),
            entry("Tried to map a mod-provided API to interface.", mod: "Content Patcher"),
        ]
        #expect(ContentPatcherConflicts.read(from: noise).isEmpty)
    }

    /// Deux journaux successifs peuvent répéter le même conflit ; une seule
    /// ligne doit en sortir.
    @Test func theSameConflictIsNotReportedTwice() throws {
        let line = entry("Two content packs want to load the 'Maps/Town' asset with the 'Exclusive' priority (A and B). Neither will be applied.")
        #expect(ContentPatcherConflicts.read(from: [line, line]).count == 1)
    }

    /// **Un nom de pack qui contient « and » rend le découpage impossible.**
    /// `(Bed and Breakfast and [CP] Simple)` se fend en trois morceaux dont deux
    /// sont des fragments d'un même nom. Le message annonce **deux** packs : si
    /// on n'en obtient pas deux, on ne sait pas où est la frontière, et une paire
    /// fausse désignerait les mauvais mods. On s'abstient.
    @Test func anAmbiguousSeparatorYieldsNothingRatherThanAWrongPair() throws {
        let found = ContentPatcherConflicts.read(from: [entry(
            "Two content packs want to load the 'Maps/Town' asset with the 'Exclusive' priority (Bed and Breakfast and [CP] Simple). Neither will be applied.")])
        #expect(found.isEmpty)
    }
}
