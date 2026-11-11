import Testing
import Foundation
@testable import StarHubTHCore

/// Incompatibilités déclarées par un mod dans le journal SMAPI
/// (« Incompatible Mod Detected: <UniqueId>. <Mod> will not load. ») : un
/// seul lecteur (`SmapiDiagnostics.parse`, `incompatibleMods`), dont les
/// Alertes et les fiches tirent les mêmes paires, puis la résolution de
/// l'uniqueId en fiche (`ModFocusResolver`). Jusqu'au 2026-11-11, un second
/// lecteur aux règles différentes servait les fiches. La ligne
/// réelle vient du journal du parc (Mastery Extended contre Skill Mastery
/// Prestige) : le nom du mod est au CROCHET DE SOURCE, pas en préfixe.
struct IncompatibleModTests {
    static let line = "[00:11:59 ERROR Mastery Extended] Incompatible Mod Detected: TimBukTwo.SkillMasteryPrestige. Mastery Extended will not load."
    static let relayed = "[00:11:59 ERROR SMAPI] Mastery Extended: Incompatible Mod Detected: TimBukTwo.SkillMasteryPrestige. Mastery Extended will not load."

    /// Les paires telles que le ViewModel les déclare sur les fiches.
    private func pairs(_ log: String) -> [(String, String)] {
        SmapiDiagnostics.parse(logContent: log).incompatibleMods.map { ($0.mod, $0.other) }
    }

    /// La paire porte le nom du mod (lu au crochet de source) et l'uniqueId
    /// de l'autre, point final de la phrase compris dans la capture.
    @Test func extractsBothSidesOfThePair() {
        let pairs = pairs(Self.line)
        #expect(pairs.count == 1)
        #expect(pairs.first?.0 == "Mastery Extended")
        #expect(pairs.first?.1 == "TimBukTwo.SkillMasteryPrestige")
    }

    /// SMAPI relayant sous son propre crochet (le nom en préfixe du message)
    /// donne la même paire.
    @Test func smapiRelayedPrefixGivesTheSamePair() {
        let pairs = pairs(Self.relayed)
        #expect(pairs.count == 1)
        #expect(pairs.first?.0 == "Mastery Extended")
        #expect(pairs.first?.1 == "TimBukTwo.SkillMasteryPrestige")
    }

    /// Une ligne répétée ne fait qu'une paire.
    @Test func repeatedLineYieldsOnePair() {
        let log = [Self.line, Self.line].joined(separator: "\r\n")
        #expect(pairs(log).count == 1)
    }

    /// Le niveau compte : un `WARN` n'est pas une déclaration — ni pour les
    /// fiches, ni pour les Alertes, qui l'acceptaient avant l'unification.
    @Test func warningsStayOut() {
        let warn = "[00:11:59 WARN  Mastery Extended] Incompatible Mod Detected: X.Y. will not load."
        #expect(pairs(warn).isEmpty)
        #expect(SmapiDiagnostics.parse(logContent: warn).problemCount == 0)
    }

    /// Sans « : » après la phrase, pas d'autre mod lisible : rien de déclaré
    /// (la paire devient une incompatibilité **persistante** sur les fiches).
    @Test func aPhraseWithoutColonDeclaresNothing() {
        #expect(pairs("[00:11:59 ERROR Mastery Extended] Incompatible mod detected, skipping.").isEmpty)
    }

    /// Sans nom de mod lisible (ni crochet, ni préfixe), pas de paire
    /// inventée : la phrase-clé ne devient jamais un nom de mod.
    @Test func missingNameYieldsNothing() {
        let log = "[00:11:59 ERROR SMAPI] Incompatible Mod Detected: X.Y. will not load."
        #expect(pairs(log).isEmpty)
    }

    /// Une casse non ASCII qui change la longueur en minuscules (« İ » →
    /// deux caractères) ne doit ni planter ni tronquer : la plage est
    /// cherchée dans le message original.
    @Test func unicodeCaseShiftDoesNotBreakTheSlice() {
        let log = "[00:11:59 ERROR SMAPI] İnal Mod: Incompatible Mod Detected: X.Y. İnal Mod will not load."
        let pairs = pairs(log)
        #expect(pairs.count == 1)
        #expect(pairs.first?.0 == "İnal Mod")
        #expect(pairs.first?.1 == "X.Y")
    }

    /// Côté Alertes : une entrée structurée portant les DEUX côtés, le
    /// message brut en preuve — pas une erreur bénigne, pas un `failed`
    /// détourné (qui ne porte qu'un nom).
    @Test func diagnosticsCarryBothSidesAndSample() {
        let d = SmapiDiagnostics.parse(logContent: Self.line)
        #expect(d.failed.isEmpty)
        #expect(d.benignNotices.isEmpty)
        #expect(d.incompatibleMods.count == 1)
        #expect(d.incompatibleMods.first?.mod == "Mastery Extended")
        #expect(d.incompatibleMods.first?.other == "TimBukTwo.SkillMasteryPrestige")
        #expect(d.incompatibleMods.first?.sample.contains("will not load") == true)
        // Un vrai problème : compte dans le total des Alertes.
        #expect(d.problemCount == 1)
    }

    /// L'identifiant ne change pas d'une lecture du journal à l'autre.
    @Test func theIdIsStableAcrossReads() {
        let first = SmapiDiagnostics.parse(logContent: Self.line).incompatibleMods.map(\.id)
        #expect(first == ["Mastery Extended|TimBukTwo.SkillMasteryPrestige"])
        #expect(SmapiDiagnostics.parse(logContent: Self.line).incompatibleMods.map(\.id) == first)
    }

    /// Une ligne répétée ne produit qu'une entrée : l'id d'alerte
    /// (`smapi-incompat-…`) serait sinon dupliqué, collision `ForEach`.
    @Test func repeatedLineCountsOnceInDiagnostics() {
        let log = [Self.line, Self.line].joined(separator: "\r\n")
        #expect(SmapiDiagnostics.parse(logContent: log).incompatibleMods.count == 1)
    }

    /// Le résolveur de fiche retrouve un mod par son uniqueId : c'est la
    /// forme sous laquelle l'autre mod est cité dans le journal.
    @Test func resolverFindsModByUniqueId() {
        let mod = ModItem(uniqueId: "TimBukTwo.SkillMasteryPrestige", name: "Skill Mastery Prestige",
                          folderName: "SkillMasteryPrestige", version: "1.0.0", author: "TimBukTwo",
                          description: "", nexusUrl: "", nexusModId: "", updateKeys: [],
                          isEnabled: true, dependencies: [])
        let hit = ModFocusResolver.resolve("TimBukTwo.SkillMasteryPrestige", in: [mod])
        #expect(hit?.folderName == "SkillMasteryPrestige")
        #expect(ModFocusResolver.uniqueMatch("timbuktwo.skillmasteryprestige", in: [mod])?.folderName == "SkillMasteryPrestige")
    }
}
