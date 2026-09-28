import Testing
import Foundation
@testable import StarHubTHCore

/// Les paires connues d'avance rejoignent les déclarées et les observées :
/// même filtrage (les deux actifs), même écartement par l'utilisateur.
struct KnownIncompatibilitiesTests {
    private func mod(_ folder: String, id: String, enabled: Bool = true) -> ModItem {
        ModItem(uniqueId: id, name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [], languages: [])
    }

    /// Les dossiers du parc réel : `StarHubFR Probe` et `.Profiler` (en pause).
    private var parc: [ModItem] {
        [mod("StarHubFR Probe", id: "mrbabilo.StarHubFR.Probe"),
         mod("Profiler", id: "sinz.profiler", enabled: false),
         mod("SpaceCore", id: "spacechase0.SpaceCore")]
    }

    @Test func probeAndProfilerFormAKnownPair() {
        #expect(KnownIncompatibilities.pairs(in: parc) == [ModConflictPair("StarHubFR Probe", "Profiler")])
        #expect(KnownIncompatibilities.pairs(in: [mod("StarHubFR Probe", id: "mrbabilo.StarHubFR.Probe")]).isEmpty)
    }

    /// Candidate dès qu'ils sont installés ; alerte seulement actifs ensemble,
    /// comme toute paire (`liveConflicts`).
    @Test func alertsOnlyWhenBothAreActive() {
        let verdicts = ModConflictVerdicts()
        let candidates = verdicts.candidates(observed: [], installed: parc)
        #expect(verdicts.liveConflicts(candidates: candidates, activeFolders: ["StarHubFR Probe"]).isEmpty)
        #expect(verdicts.liveConflicts(candidates: candidates,
                                       activeFolders: ["StarHubFR Probe", "Profiler"]).count == 1)
    }

    /// L'utilisateur garde la main : une paire connue s'écarte comme une autre.
    @Test func aKnownPairCanBeDismissed() {
        var verdicts = ModConflictVerdicts()
        verdicts.dismiss(ModConflictPair("Profiler", "StarHubFR Probe"), note: "", at: Date())
        let candidates = verdicts.candidates(observed: [], installed: parc)
        #expect(verdicts.liveConflicts(candidates: candidates,
                                       activeFolders: ["StarHubFR Probe", "Profiler"]).isEmpty)
    }

    /// Déclarées et observées restent candidates, sans doublon quand une
    /// paire connue a aussi été déclarée.
    @Test func candidatesKeepDeclaredAndObserved() {
        var verdicts = ModConflictVerdicts()
        verdicts.declare(ModConflictPair("StarHubFR Probe", "Profiler"), note: "", at: Date())
        let observed = [ModConflictPair("A", "B")]
        let candidates = verdicts.candidates(observed: observed, installed: parc)
        #expect(Set(candidates) == [ModConflictPair("StarHubFR Probe", "Profiler"), ModConflictPair("A", "B")])
        #expect(candidates.count == 2)
    }

    /// Ce que l'écran liste comme « connue » : ni déclarée (elle a sa ligne
    /// « Signalé par vous »), ni écartée ; et la raison qui l'accompagne.
    @Test func knownPairsExcludeDeclaredAndDismissedAndCarryAReason() {
        let pair = ModConflictPair("StarHubFR Probe", "Profiler")
        #expect(ModConflictVerdicts().knownPairs(installed: parc) == [pair])
        var declared = ModConflictVerdicts()
        declared.declare(pair, note: "", at: Date())
        #expect(declared.knownPairs(installed: parc).isEmpty)
        var dismissed = ModConflictVerdicts()
        dismissed.dismiss(pair, note: "", at: Date())
        #expect(dismissed.knownPairs(installed: parc).isEmpty)
        #expect(KnownIncompatibilities.reasonKey(for: pair, in: parc) == "conflicts_known_probe_profiler")
        #expect(KnownIncompatibilities.reasonKey(for: ModConflictPair("A", "B"), in: parc) == nil)
    }
}
