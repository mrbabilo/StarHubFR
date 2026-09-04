import Testing
import Foundation
@testable import StarHubTHCore

/// Le seul levier qui mord sur le parc réel : **le nombre gardé par mod**.
/// Mesuré le 2026-09-04 sur 923 sauvegardes — garder 1 libère 723 Mo (40 %),
/// garder 3 en libère 218, garder 5 en libère 24. Une purge par âge rendrait
/// **0 Mo** : 922 des 923 ont moins de 30 jours.
struct PurgePlanTests {

    private func e(_ id: String, _ mod: String, day: Int, mb: Int64,
                   files: [MaintenanceInventory.UserFile] = [])
    -> MaintenanceInventory.BackupEntry {
        .init(id: id, modFolder: mod,
              timestamp: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
              sizeBytes: mb * 1_000_000, userFiles: files)
    }

    @Test func keepingOnePerModLeavesTheMostRecentOfEachMod() {
        let entries = [e("a1", "Realistic Nature", day: 3, mb: 60),
                       e("a2", "Realistic Nature", day: 1, mb: 55),
                       e("a3", "Realistic Nature", day: 2, mb: 57),
                       e("b1", "Cropgenics", day: 5, mb: 40)]
        let plan = MaintenanceInventory.plan(keepPerMod: 1, entries: entries, protections: [:])
        #expect(Set(plan.doomed.map(\.id)) == ["a2", "a3"])
        #expect(plan.freedBytes == 112_000_000)
    }

    @Test func aModWithASingleBackupIsNeverTouched() {
        let entries = [e("only", "MarketBeauties", day: 1, mb: 304)]
        for keep in 1...5 {
            let plan = MaintenanceInventory.plan(keepPerMod: keep, entries: entries, protections: [:])
            #expect(plan.doomed.isEmpty)
            #expect(plan.freedBytes == 0)
        }
    }

    @Test func aProtectedBackupIsNeitherRemovedNorCounted() {
        // Le gain annoncé doit exclure ce qu'on refuse de retirer : sinon
        // l'écran promet un espace qu'il ne rendra pas.
        let file = MaintenanceInventory.UserFile(relativePath: "config.json", kind: .config)
        let entries = [e("keep", "Zebrus", day: 3, mb: 10),
                       e("prot", "Zebrus", day: 2, mb: 7, files: [file]),
                       e("gone", "Zebrus", day: 1, mb: 5)]
        let plan = MaintenanceInventory.plan(
            keepPerMod: 1, entries: entries,
            protections: ["prot": .soleCopy([file])])
        #expect(plan.doomed.map(\.id) == ["gone"])
        #expect(plan.freedBytes == 5_000_000)
        #expect(plan.protectedCount == 1)
    }

    @Test func aProtectedBackupDoesNotConsumeAKeptSlot() {
        // Elle survit **en plus** du quota : garder 1 signifie une sauvegarde
        // libre conservée, pas « la protégée tient lieu de la gardée ».
        let file = MaintenanceInventory.UserFile(relativePath: "config.json", kind: .config)
        let entries = [e("prot", "Zebrus", day: 3, mb: 7, files: [file]),
                       e("recent", "Zebrus", day: 2, mb: 10),
                       e("old", "Zebrus", day: 1, mb: 5)]
        let plan = MaintenanceInventory.plan(
            keepPerMod: 1, entries: entries,
            protections: ["prot": .soleCopy([file])])
        #expect(plan.doomed.map(\.id) == ["old"])
    }

    @Test func keepingMoreThanExistsRemovesNothing() {
        let entries = [e("a", "M", day: 2, mb: 1), e("b", "M", day: 1, mb: 1)]
        let plan = MaintenanceInventory.plan(keepPerMod: 5, entries: entries, protections: [:])
        #expect(plan.doomed.isEmpty)
    }

    @Test func inputOrderDoesNotChangeTheOutcome() {
        let forward = [e("a", "M", day: 1, mb: 1), e("b", "M", day: 2, mb: 2),
                       e("c", "M", day: 3, mb: 3)]
        let planA = MaintenanceInventory.plan(keepPerMod: 1, entries: forward, protections: [:])
        let planB = MaintenanceInventory.plan(keepPerMod: 1, entries: forward.reversed(),
                                              protections: [:])
        #expect(Set(planA.doomed.map(\.id)) == Set(planB.doomed.map(\.id)))
        #expect(planA.freedBytes == planB.freedBytes)
    }

    @Test func keepPerModIsClampedToAtLeastOne() {
        // Zéro gardé effacerait tout l'historique d'un mod : la borne est dans
        // la règle, pas dans l'interface qui l'appelle.
        let entries = [e("a", "M", day: 2, mb: 1), e("b", "M", day: 1, mb: 1)]
        let plan = MaintenanceInventory.plan(keepPerMod: 0, entries: entries, protections: [:])
        #expect(plan.doomed.map(\.id) == ["b"])
    }
}
