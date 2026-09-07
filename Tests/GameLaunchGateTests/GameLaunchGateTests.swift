import Testing
import Foundation
@testable import StarHubTHCore

/// R2bis — le bouton de lancement ne doit jamais créer une seconde instance
/// du jeu. Deux couches : le garde « jeu déjà en cours » (le VM interroge
/// `isGameRunning()`) et ce **délai**, qui ponte la fenêtre où le processus
/// lancé n'apparaît pas encore dans `NSWorkspace.runningApplications` —
/// quelques secondes pendant lesquelles un double-clic passe sinon librement.
@Suite struct GameLaunchGateTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func firstLaunchIsAdmitted() {
        var gate = GameLaunchGate()
        #expect(gate.admit(now: t0) == true)
    }

    @Test func aDoubleClickWithinTheWindowIsRefused() {
        var gate = GameLaunchGate()
        _ = gate.admit(now: t0)
        #expect(gate.admit(now: t0.addingTimeInterval(2)) == false)
        // …et la fenêtre ne se rallonge pas d'un refus : elle part du
        // **premier** essai admis, pas du dernier clic refusé.
        #expect(gate.admit(now: t0.addingTimeInterval(4)) == false)
    }

    @Test func aLaunchAfterTheWindowIsAdmittedAgain() {
        var gate = GameLaunchGate()
        _ = gate.admit(now: t0)
        #expect(gate.admit(now: t0.addingTimeInterval(20)) == true)
    }

    @Test func theWindowEdgeIsExactlyTheCooldown() {
        var gate = GameLaunchGate()
        _ = gate.admit(now: t0)
        #expect(gate.admit(now: t0.addingTimeInterval(GameLaunchGate.cooldown - 0.001)) == false)
        #expect(gate.admit(now: t0.addingTimeInterval(GameLaunchGate.cooldown)) == true)
    }

    @Test func noticeGameRunningReopensTheGateImmediately() {
        // Le jeu a fini par apparaître : c'est désormais le garde
        // `isGameRunning()` du VM qui protège, et un crash immédiat suivi
        // d'un relancement légitime ne doit pas attendre le délai complet.
        var gate = GameLaunchGate()
        _ = gate.admit(now: t0)
        gate.noticeGameRunning()
        #expect(gate.admit(now: t0.addingTimeInterval(1)) == true)
    }
}
