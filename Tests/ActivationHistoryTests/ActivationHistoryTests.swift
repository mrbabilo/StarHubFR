import Testing
import Foundation
@testable import StarHubTHCore

/// R5 — revenir à l'état actif/en pause d'avant un geste de masse.
///
/// Le reste existe déjà (historique par mod, backups d'installation,
/// corbeille, backups de config, journal de reprise de profil) : seul
/// manquait le retour d'un « Tout activer » ou d'un profil appliqué.
struct ActivationHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_417_600)
    private let day: TimeInterval = 86_400

    private func mod(_ folder: String, enabled: Bool, id: String? = nil) -> ModItem {
        ModItem(uniqueId: id ?? folder.lowercased(), name: folder, folderName: folder, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    private func snapshot(_ mods: [ModItem], at date: Date, profile: UUID? = nil,
                          gesture: ActivationSnapshot.Gesture = .bulkEnable) -> ActivationSnapshot {
        ActivationSnapshot.capture(gesture: gesture, detail: nil, mods: mods,
                                   activeProfileId: profile, now: date)
    }

    // MARK: - Capture

    @Test func captureSplitsTopFoldersByState() {
        let s = snapshot([mod("A", enabled: true), mod("B", enabled: false)], at: t0)
        #expect(s.enabledFolders == ["A"])
        #expect(s.pausedFolders == ["B"])
        #expect(!s.pinned)
    }

    // MARK: - Plan de retour

    @Test func restoreReversesWhatTheGestureMoved() {
        let before = [mod("A", enabled: false), mod("B", enabled: true)]
        let s = snapshot(before, at: t0)
        let now = [mod("A", enabled: true), mod("B", enabled: false)]
        let moves = ActivationRestore.moves(to: s, installed: now)
        #expect(moves.map(\.folderName) == ["A", "B"])
        // Les mises en pause d'abord : elles libèrent un nom de dossier.
        #expect(moves.map(\.direction) == [.disable, .enable])
        #expect(moves[0].destination == ".A")
        #expect(moves[1].source == ".B" && moves[1].destination == "B")
    }

    @Test func aModInstalledAfterTheSnapshotKeepsItsState() {
        // Inconnu de l'instantané : ni activé ni mis en pause par le retour.
        let s = snapshot([mod("A", enabled: true)], at: t0)
        let moves = ActivationRestore.moves(to: s, installed: [mod("A", enabled: true),
                                                                mod("New", enabled: true)])
        #expect(moves.isEmpty)
    }

    @Test func aModRemovedSinceIsIgnored() {
        let s = snapshot([mod("A", enabled: true), mod("Gone", enabled: true)], at: t0)
        let moves = ActivationRestore.moves(to: s, installed: [mod("A", enabled: false)])
        #expect(moves.map(\.folderName) == ["A"])
    }

    @Test func aModWithoutUniqueIdIsRestoredByFolder() {
        // 111 mods du parc n'ont pas d'UniqueID : un profil ne peut pas les
        // couvrir, le retour par dossier si.
        let s = snapshot([mod("NoId", enabled: false, id: "")], at: t0)
        let moves = ActivationRestore.moves(to: s, installed: [mod("NoId", enabled: true, id: "")])
        #expect(moves.map(\.direction) == [.disable])
    }

    @Test func smapiBundledModsAreNeverPaused() {
        let s = snapshot([mod("ConsoleCommands", enabled: false, id: "SMAPI.ConsoleCommands")], at: t0)
        let moves = ActivationRestore.moves(
            to: s, installed: [mod("ConsoleCommands", enabled: true, id: "SMAPI.ConsoleCommands")])
        #expect(moves.isEmpty)
    }

    // MARK: - Historique

    @Test func newestSnapshotComesFirst() {
        var h = ActivationHistory()
        h.record(snapshot([mod("A", enabled: true)], at: t0), now: t0)
        h.record(snapshot([mod("A", enabled: false)], at: t0 + 60), now: t0 + 60)
        #expect(h.snapshots.map(\.takenAt) == [t0 + 60, t0])
    }

    @Test func anIdenticalStateIsNotRecordedTwice() {
        var h = ActivationHistory()
        h.record(snapshot([mod("A", enabled: true)], at: t0), now: t0)
        h.record(snapshot([mod("A", enabled: true)], at: t0 + 60, gesture: .profile), now: t0 + 60)
        #expect(h.snapshots.count == 1)
    }

    @Test func unpinnedSnapshotsOlderThanThirtyDaysArePruned() {
        var h = ActivationHistory()
        h.record(snapshot([mod("A", enabled: true)], at: t0), now: t0)
        h.record(snapshot([mod("A", enabled: false)], at: t0 + 31 * day), now: t0 + 31 * day)
        #expect(h.snapshots.count == 1)
    }

    @Test func aPinnedSnapshotSurvivesPruning() {
        var h = ActivationHistory()
        let old = snapshot([mod("A", enabled: true)], at: t0)
        h.record(old, now: t0)
        h.setPinned(old.id, true)
        h.record(snapshot([mod("A", enabled: false)], at: t0 + 31 * day), now: t0 + 31 * day)
        #expect(h.snapshots.map(\.id).contains(old.id))
    }

    @Test func unpinnedSnapshotsAreCapped() {
        var h = ActivationHistory()
        for i in 0..<(ActivationHistory.maxUnpinned + 5) {
            let date = t0 + Double(i)
            h.record(snapshot([mod("A", enabled: i % 2 == 0)], at: date), now: date)
        }
        #expect(h.snapshots.count == ActivationHistory.maxUnpinned)
        // Les plus anciens partent.
        #expect(h.snapshots.last?.takenAt == t0 + 5)
    }

    @Test func pinnedSnapshotsDoNotCountTowardsTheCap() {
        var h = ActivationHistory()
        let first = snapshot([mod("A", enabled: false)], at: t0 - 1)
        h.record(first, now: t0 - 1)
        h.setPinned(first.id, true)
        for i in 0..<ActivationHistory.maxUnpinned {
            let date = t0 + Double(i)
            h.record(snapshot([mod("A", enabled: i % 2 == 0)], at: date), now: date)
        }
        #expect(h.snapshots.count == ActivationHistory.maxUnpinned + 1)
    }
}
