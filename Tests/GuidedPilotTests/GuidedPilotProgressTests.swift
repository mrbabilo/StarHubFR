import Testing
import Foundation
@testable import StarHubTHCore

/// Les étapes visibles d'un côté piloté, du clic à la mesure : le jeu met
/// minutes à charger ~900 mods — sans elles, l'utilisateur croit que rien ne
/// se passe (retour du 2026-10-13). Signaux : processus du jeu, puis les
/// lignes de `loads.jsonl` que la sonde écrit à l'écran titre et au monde prêt.
@Suite struct GuidedPilotProgressTests {
    private let launched = Date(timeIntervalSince1970: 1_000)

    private func record(_ kind: ProbeLoadRecord.Kind, at seconds: TimeInterval?) -> ProbeLoadRecord {
        ProbeLoadRecord(kind: kind, session: "s", atText: "", at: seconds.map { launched.addingTimeInterval($0) },
                        probeVersion: "0.9.26", complete: true, reload: false,
                        saveName: kind == .save ? "Ferme" : nil, patchesMeasured: false,
                        saveBytes: nil, saveDate: nil, milestones: [], phases: [], final: nil,
                        health: .init(packSeam: "ok", assetHook: "ok", loadHook: "ok", offThreadSections: 0))
    }

    @Test func launchingUntilTheGameProcessAppears() {
        #expect(GuidedPilotProgress.stage(launchedAt: launched, gameRunning: false, loads: []) == .launching)
    }

    /// Les chargements d'avant le lancement (côté précédent) ne comptent pas.
    @Test func loadingModsWhileNoRecordOfThisLaunch() {
        let old = [record(.launch, at: -300), record(.save, at: -250)]
        #expect(GuidedPilotProgress.stage(launchedAt: launched, gameRunning: true, loads: old) == .loadingMods)
    }

    @Test func loadingSaveOnceTheTitleScreenIsReached() {
        let loads = [record(.launch, at: 90)]
        #expect(GuidedPilotProgress.stage(launchedAt: launched, gameRunning: true, loads: loads) == .loadingSave)
    }

    @Test func measuringOnceTheSaveIsLoaded() {
        let loads = [record(.launch, at: 90), record(.save, at: 140)]
        #expect(GuidedPilotProgress.stage(launchedAt: launched, gameRunning: true, loads: loads) == .measuring)
    }

    /// Ligne sans date lisible : ignorée, pas prise pour une étape franchie.
    @Test func undatedRecordsAreIgnored() {
        let loads = [record(.launch, at: nil)]
        #expect(GuidedPilotProgress.stage(launchedAt: launched, gameRunning: true, loads: loads) == .loadingMods)
    }

    @Test func stagesAreOrdered() {
        #expect(GuidedPilotProgress.Stage.allCases == [.launching, .loadingMods, .loadingSave, .measuring])
    }
}
