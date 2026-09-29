import Testing
import Foundation
@testable import StarHubTHCore

struct ProbeAnalysisTests {
    /// Fabrique des entrées cohérentes ; chaque cas n'en surcharge qu'un champ.
    private func input(
        verdict: ProbeMeasureComparison.Verdict = .netChange(delta: 3, percent: 10),
        diff: ProbeInventoryDiff = ProbeInventoryDiff(probeChanged: false, changes: []),
        costs: [ProbeCostDelta] = [],
        keptA: Int = 15, keptB: Int = 15,
        locationsRestricted: Bool = true,
        measurement: ProbeMeasurement? = nil,
        patchesMismatch: Bool = false, dominantLocation: String? = nil,
        workVerdict: ProbeMeasureComparison.Verdict = .noise,
        updatesPerSecond: (a: Double, b: Double)? = nil
    ) -> ProbeAnalysisInput {
        let a = ProbeSideSummary(count: keptA, median: 30, q1: 29, q3: 31)
        let b = ProbeSideSummary(count: keptB, median: 33, q1: 32, q3: 34)
        func measure(_ verdict: ProbeMeasureComparison.Verdict) -> ProbeMeasureComparison {
            ProbeMeasureComparison(a: a, b: b, verdict: verdict)
        }
        let rates = ProbeMeasureComparison(
            a: ProbeSideSummary(count: keptA, median: updatesPerSecond?.a, q1: nil, q3: nil),
            b: ProbeSideSummary(count: keptB, median: updatesPerSecond?.b, q1: nil, q3: nil),
            verdict: .noise)
        let comparison = ProbeComparison(
            frameP50: measure(verdict), frameP99: measure(.noise), workP50: measure(workVerdict),
            fps: measure(.noise), heap: measure(.noise), updatesPerSecond: rates, vsyncLimited: false,
            patchesMismatch: patchesMismatch, verdict: verdict)
        return ProbeAnalysisInput(comparison: comparison, diff: diff, costDeltas: costs,
                                  exclusionsA: [:], exclusionsB: [:],
                                  locationsRestricted: locationsRestricted,
                                  measurement: measurement, dominantLocation: dominantLocation)
    }

    private func diff(_ changes: ProbeModChange...) -> ProbeInventoryDiff {
        ProbeInventoryDiff(probeChanged: false, changes: changes)
    }
    private func added(_ id: String) -> ProbeInventoryDiff { diff(ProbeModChange(modId: id, kind: .added)) }

    // 1. Conclusion
    @Test func slowerFasterNoDifferenceInconclusive() {
        #expect(ProbeAnalysis.analyze(input(verdict: .netChange(delta: 3, percent: 10))).direction == .slower(percent: 10))
        #expect(ProbeAnalysis.analyze(input(verdict: .netChange(delta: -3, percent: -10))).direction == .faster(percent: 10))
        #expect(ProbeAnalysis.analyze(input(verdict: .noise)).direction == .noDifference)
        #expect(ProbeAnalysis.analyze(input(verdict: .notEnoughData)).direction == .inconclusive)
    }

    // 2. Confiance, bornes comprises (15 minutes).
    @Test func confidenceLevels() {
        // Élevée : mesure propre OU ≥ 15 minutes de chaque côté, même lieu.
        #expect(ProbeAnalysis.analyze(input()).confidence == .high)
        #expect(ProbeAnalysis.analyze(input(keptA: 8, keptB: 8,
                                            measurement: ProbeMeasurement(name: "m", start: .now, end: nil)))
                .confidence == .high)
        // Moyenne : 5 à 14 minutes, ou lieux différents.
        #expect(ProbeAnalysis.analyze(input(keptA: 14, keptB: 15)).confidence == .medium)
        #expect(ProbeAnalysis.analyze(input(keptA: 5, keptB: 5)).confidence == .medium)
        #expect(ProbeAnalysis.analyze(input(locationsRestricted: false)).confidence == .medium)
        // Faible : sonde changée.
        let probe = ProbeInventoryDiff(probeChanged: true, changes: [])
        let probeResult = ProbeAnalysis.analyze(input(diff: probe))
        #expect(probeResult.confidence == .low)
        #expect(probeResult.evidence.contains(.probeChanged))
        // Faible : ≥ 3 changements ; 2 ne suffisent pas.
        let three = ProbeInventoryDiff(probeChanged: false, changes: (0..<3).map {
            ProbeModChange(modId: "Mod.\($0)", kind: .added) })
        #expect(ProbeAnalysis.analyze(input(diff: three)).confidence == .low)
        #expect(ProbeAnalysis.analyze(input(diff: three)).evidence.filter { $0 == .changeCount(3) }.count == 1)
        let two = ProbeInventoryDiff(probeChanged: false, changes: Array(three.changes.prefix(2)))
        #expect(ProbeAnalysis.analyze(input(diff: two)).confidence == .high)
    }

    // 3. Attribution
    @Test func singleChangeIsNamedCause() {
        let result = ProbeAnalysis.analyze(input(diff: added("UltraSmooth"),
                                                 costs: [ProbeCostDelta(modId: "UltraSmooth",
                                                                        msPerSecondA: nil, msPerSecondB: 0.8, presence: .added)]))
        #expect(result.evidence.contains(.singleChange(modId: "UltraSmooth")))
        #expect(result.evidence.contains(.directCost(modId: "UltraSmooth", deltaMsPerSecond: 0.8)))
        #expect(result.recommendation == .disableMod(modId: "UltraSmooth"))
    }

    /// Plusieurs changements : classés par coût direct — des **mods changés**
    /// seulement, identifiants comparés sans la casse ; le coût d'un mod non
    /// changé (bruit du parc) n'entre pas en preuve.
    @Test func multipleChangesRankedByTheirOwnDirectCost() {
        let costs = [
            ProbeCostDelta(modId: "Unchanged.Mod", msPerSecondA: 1, msPerSecondB: 4, presence: .both),
            ProbeCostDelta(modId: "Mod.B", msPerSecondA: nil, msPerSecondB: 0.5, presence: .added),
            ProbeCostDelta(modId: "mod.a", msPerSecondA: nil, msPerSecondB: 2, presence: .added),
        ]
        let result = ProbeAnalysis.analyze(input(
            diff: diff(ProbeModChange(modId: "Mod.A", kind: .added), ProbeModChange(modId: "Mod.B", kind: .added)),
            costs: costs))
        let direct = result.evidence.compactMap { evidence -> String? in
            if case .directCost(let id, _) = evidence { return id } else { return nil }
        }
        #expect(direct == ["mod.a", "Mod.B"])
        #expect(result.evidence.contains(.changeCount(2)))
        #expect(result.recommendation == .isolate)
    }

    // 4. Recommandations (table de la spec)
    @Test func recommendationTable() {
        // Un seul mod mis à jour, plus lent, net → revenir à la version d'avant.
        let updated = diff(ProbeModChange(modId: "Mod.X", kind: .versionChanged(from: "1.0", to: "1.1")))
        #expect(ProbeAnalysis.analyze(input(diff: updated)).recommendation == .revertVersion(modId: "Mod.X"))

        // Un seul réglage changé → revenir au réglage d'avant.
        let config = diff(ProbeModChange(modId: "Mod.C", kind: .configChanged(oldSha: "aa", newSha: "bb")))
        #expect(ProbeAnalysis.analyze(input(diff: config)).recommendation == .revertConfig(modId: "Mod.C"))

        // Plus rapide, net → garder, même avec plusieurs changements.
        let faster = ProbeMeasureComparison.Verdict.netChange(delta: -3, percent: -10)
        #expect(ProbeAnalysis.analyze(input(verdict: faster, diff: added("Mod.C"))).recommendation == .keep)
        let two = diff(ProbeModChange(modId: "Mod.A", kind: .added), ProbeModChange(modId: "Mod.B", kind: .added))
        #expect(ProbeAnalysis.analyze(input(verdict: faster, diff: two)).recommendation == .keep)

        // Pas de différence, un mod ajouté → garder, coût pour mémoire.
        #expect(ProbeAnalysis.analyze(input(verdict: .noise, diff: added("Mod.C"))).recommendation
                == .keepNoCost(modId: "Mod.C"))

        // Pas de différence, un réglage perf changé → « n'apporte rien ».
        #expect(ProbeAnalysis.analyze(input(verdict: .noise, diff: config)).recommendation
                == .configNoGain(modId: "Mod.C"))

        // Confiance faible → refaire une mesure propre (protocole : les
        // minutes qui manquent pour atteindre 15 de chaque côté — ici zéro,
        // c'est la sonde changée qui bloque, pas le volume).
        let probe = ProbeInventoryDiff(probeChanged: true, changes: [])
        #expect(ProbeAnalysis.analyze(input(diff: probe)).recommendation
                == .rerunCleanMeasurement(location: nil, missingMinutes: 0))

        // Pas assez de données → refaire, avec le compte qui manque.
        #expect(ProbeAnalysis.analyze(input(verdict: .notEnoughData, keptA: 3, keptB: 7)).recommendation
                == .rerunCleanMeasurement(location: nil, missingMinutes: 12))
    }

    /// Les unités : le travail de trame est en ms **par tick**, le coût
    /// direct en ms **par seconde**. +0,8 ms/s (le cas UltraSmooth) ne pèse
    /// que 0,013 ms par tick : sur 1 ms d'écart, la part indirecte domine.
    @Test func directCostIsConvertedToPerTickBeforeTheIndirectShare() {
        let result = ProbeAnalysis.analyze(input(
            diff: added("Mod.A"),
            costs: [ProbeCostDelta(modId: "Mod.A", msPerSecondA: nil, msPerSecondB: 0.8, presence: .added)],
            workVerdict: .netChange(delta: 1, percent: 11.1)))
        #expect(result.evidence.contains(.indirectShare(0.99)))
    }

    /// Enveloppes actives d'un seul côté (`patchesMismatch`) : confiance
    /// faible, protocole.
    @Test func asymmetricEnvelopesForceLowConfidence() {
        let result = ProbeAnalysis.analyze(input(patchesMismatch: true))
        #expect(result.confidence == .low)
        #expect(result.evidence.contains(.envelopesAsymmetric))
        #expect(result.recommendation == .rerunCleanMeasurement(location: nil, missingMinutes: 0))
    }

    /// Part indirecte dominante : la recommandation repasse au protocole,
    /// avec le lieu à mesurer.
    @Test func indirectDominantSendsBackToProtocol() {
        // Travail de trame +1 ms par tick ; coût direct du seul changement
        // +12 ms/s, soit 0,2 ms par tick à 60 ticks/s : la part indirecte
        // (0,8) dépasse la moitié de l'écart.
        let result = ProbeAnalysis.analyze(input(
            diff: added("Mod.A"),
            costs: [ProbeCostDelta(modId: "Mod.A", msPerSecondA: nil, msPerSecondB: 12, presence: .added)],
            dominantLocation: "Farm",
            workVerdict: .netChange(delta: 1, percent: 11.1)))
        #expect(result.evidence.contains(.indirectShare(0.8)))
        #expect(result.recommendation == .rerunCleanMeasurement(location: "Farm", missingMinutes: 0))
    }

    /// Coûts non mesurés d'un côté (`costDeltas` vide) : aucune part
    /// indirecte inventée — tout l'écart n'est pas « hors des mods ».
    @Test func noIndirectShareWithoutMeasuredCosts() {
        let result = ProbeAnalysis.analyze(input(
            diff: added("Mod.A"), costs: [], workVerdict: .netChange(delta: 1, percent: 11.1)))
        #expect(!result.evidence.contains { if case .indirectShare = $0 { true } else { false } })
    }

    /// Borne : une part indirecte d'exactement la moitié n'est pas dominante
    /// (30 ms/s = 0,5 ms par tick, pour 1 ms d'écart de travail).
    @Test func indirectShareAtHalfIsNotDominant() {
        let result = ProbeAnalysis.analyze(input(
            diff: added("Mod.A"),
            costs: [ProbeCostDelta(modId: "Mod.A", msPerSecondA: nil, msPerSecondB: 30, presence: .added)],
            workVerdict: .netChange(delta: 1, percent: 11.1)))
        #expect(!result.evidence.contains { if case .indirectShare = $0 { true } else { false } })
        #expect(result.recommendation == .disableMod(modId: "Mod.A"))
    }

    /// Garde-fous : le bruit ne recommande jamais d'agir sur un mod non
    /// ajouté ; un écart « net » sous 5 % n'est jamais une raison d'agir.
    @Test func noiseAndSmallChangesNeverRecommendAction() {
        let updated = diff(ProbeModChange(modId: "Mod.X", kind: .versionChanged(from: "1.0", to: "1.1")))
        #expect(ProbeAnalysis.analyze(input(verdict: .noise, diff: updated)).recommendation == .keep)
        #expect(ProbeAnalysis.analyze(input(verdict: .netChange(delta: 1, percent: 4.9), diff: updated))
                .recommendation == .keep)
    }

    /// Une mesure propre ne vaut confiance élevée qu'avec 5 minutes de chaque
    /// côté : sinon « confiance élevée » s'afficherait à côté de « on ne peut
    /// pas conclure ».
    @Test func cleanMeasurementNeedsFiveMinutesEachSide() {
        let clean = ProbeMeasurement(name: "m", start: .now, end: nil)
        #expect(ProbeAnalysis.analyze(input(verdict: .notEnoughData, keptA: 3, keptB: 7,
                                            measurement: clean)).confidence == .low)
    }

    /// Les raisons d'exclusion entrent en preuve dès qu'une minute a été écartée.
    @Test func exclusionsBecomeEvidence() {
        let base = input()
        let withExclusions = ProbeAnalysisInput(
            comparison: base.comparison, diff: base.diff, costDeltas: [],
            exclusionsA: [.menuOpen: 3], exclusionsB: [:], locationsRestricted: true,
            measurement: nil, dominantLocation: nil)
        #expect(ProbeAnalysis.analyze(withExclusions).evidence
                .contains(.excludedMinutes(a: [.menuOpen: 3], b: [:])))
        #expect(!ProbeAnalysis.analyze(base).evidence
                .contains { if case .excludedMinutes = $0 { true } else { false } })
    }

    /// Trame nettement plus lente, travail de trame inchangé : le temps passe
    /// hors Update/Draw (GC, synchro) — dit en preuve.
    @Test func frameChangeWithoutWorkChangeIsFlagged() {
        #expect(ProbeAnalysis.analyze(input(workVerdict: .noise)).evidence.contains(.frameWorkUnchanged))
        #expect(!ProbeAnalysis.analyze(input(workVerdict: .netChange(delta: 3, percent: 10)))
                .evidence.contains(.frameWorkUnchanged))
        #expect(!ProbeAnalysis.analyze(input(verdict: .noise, workVerdict: .noise))
                .evidence.contains(.frameWorkUnchanged))
    }

    /// X117 — la cadence mesurée, pas 60 : en pas variable (UltraSmooth 2.3.9)
    /// les ticks suivent les trames. À 30 ticks/s, 12 ms/s pèsent 0,4 ms par
    /// tick : la part indirecte d'un écart de 1 ms tombe à 0,6.
    @Test func directCostUsesTheMeasuredTickRate() {
        let result = ProbeAnalysis.analyze(input(
            diff: added("Mod.A"),
            costs: [ProbeCostDelta(modId: "Mod.A", msPerSecondA: nil, msPerSecondB: 12, presence: .added)],
            workVerdict: .netChange(delta: 1, percent: 11.1),
            updatesPerSecond: (a: 30, b: 30)))
        #expect(result.evidence.contains(.indirectShare(0.6)))
    }
}
