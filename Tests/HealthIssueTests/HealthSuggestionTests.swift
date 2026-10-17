import Testing
@testable import StarHubTHCore

/// N-09 S9 — les conseils de la Santé et leur geste. Le traducteur rend la
/// clé : le texte d'un conseil y désigne sa famille.
@Suite("HealthSuggestion")
struct HealthSuggestionTests {
    private func list(_ d: SmapiDiagnostics) -> [HealthSuggestion] {
        HealthSuggestion.list(from: d, localized: { $0 })
    }

    @Test func eachKindCarriesItsGesture() {
        var d = SmapiDiagnostics()
        d.missingDeps = [.init(mod: "(AT) Forage", missing: "PeacefulEnd.AlternativeTextures")]
        d.skipped = [.init(name: "Skip", reason: "whatever")]
        d.brokenMods = ["Broken"]
        d.externalConflicts = ["RivaTuner Statistics Server"]
        d.saveSerializerMods = ["SpaceCore"]
        #expect(list(d).map(\.action) == [
            .installDependency(missing: "PeacefulEnd.AlternativeTextures"),
            .openMod("Skip"),
            .showBlock("blocking"),
            nil,
            .openMod("SpaceCore")
        ])
    }

    /// Le mod qui a déjà son conseil de dépendance n'en reçoit pas un second.
    @Test func aModCoveredByAMissingDependencyIsNotRepeated() {
        var d = SmapiDiagnostics()
        d.missingDeps = [.init(mod: "A", missing: "Some.Library")]
        d.skipped = [.init(name: "A", reason: "requires Some.Library (not installed)")]
        d.failed = [.init(name: "B", reason: "boom")]
        #expect(list(d).map(\.action) == [.installDependency(missing: "Some.Library"), .openMod("B")])
    }

    @Test func thresholdsGateTheErrorAndPatchedAdvice() {
        var d = SmapiDiagnostics()
        d.topErrorMods = [.init(name: "Noisy", count: 4)]
        d.patchedMods = Array(repeating: "p", count: 14)
        #expect(list(d).isEmpty)
        d.topErrorMods = [.init(name: "Noisy", count: 5)]
        d.patchedMods.append("p")
        #expect(list(d).map(\.action) == [.openMod("Noisy"), .showBisection])
    }

    /// Plafond : six conseils, puis une ligne « … et N autres » sans geste.
    @Test func longListsCollapseWithTheHiddenCount() {
        var d = SmapiDiagnostics()
        d.saveSerializerMods = (1...9).map { "M\($0)" }
        let out = HealthSuggestion.list(from: d, localized: { $0 == L10n.Logs.healthAndMore ? "+%lld" : $0 })
        #expect(out.count == HealthSuggestion.maxShown + 1)
        #expect(out.last == HealthSuggestion(text: "+3", action: nil))
    }

    @Test func recognisedFailuresGetTheirInstructionOthersQuoteTheReason() {
        for rule in HealthSuggestion.adviceRules {
            let issue = SmapiDiagnostics.Issue(name: "X", reason: "Because \(rule.patterns[0].uppercased())")
            #expect(HealthSuggestion.advice(for: issue, fallback: "fallback", localized: { $0 }) == rule.key)
        }
        let unknown = SmapiDiagnostics.Issue(name: "X", reason: "cosmic ray")
        #expect(HealthSuggestion.advice(for: unknown, fallback: "%1$@ (%2$@)", localized: { $0 }) == "X (cosmic ray)")
    }

    /// Le journal date : la dépendance installée depuis ne garde pas un bouton
    /// actif. Comparaison sans casse, liste séparée par des virgules.
    @Test func stillMissingIsReadFromTheDiskPlan() {
        let plan = [MissingDependency(uniqueIds: ["PeacefulEnd.AlternativeTextures"], name: "AT",
                                      nexusId: 9246, requiredBy: ["(AT) Forage"])]
        #expect(HealthSuggestion.isStillMissing("peacefulend.alternativetextures", in: plan))
        #expect(HealthSuggestion.isStillMissing("Other.Mod, PeacefulEnd.AlternativeTextures", in: plan))
        #expect(!HealthSuggestion.isStillMissing("Other.Mod", in: plan))
        #expect(!HealthSuggestion.isStillMissing("PeacefulEnd.AlternativeTextures", in: []))
    }
}
