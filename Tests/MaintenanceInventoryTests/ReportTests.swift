import Testing
import Foundation
@testable import StarHubTHCore

struct ReportTests {

    private func e(_ id: String, _ mod: String, day: Int, mb: Int64)
    -> MaintenanceInventory.BackupEntry {
        .init(id: id, modFolder: mod,
              timestamp: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
              sizeBytes: mb * 1_000_000, userFiles: [])
    }

    @Test func theTotalAddsEveryFamily() {
        let report = MaintenanceInventory.Report(
            backups: [e("a", "M", day: 1, mb: 10)],
            protections: [:],
            configBackupCount: 5,
            configBackupBytes: 42_000_000,
            orphanSessions: ["x"],
            stalePreferenceKeys: ["Disparu"])
        #expect(report.totalBytes == 52_000_000)
    }

    @Test func eachRungAnnouncesItsOwnGain() {
        // Les trois crans de l'écran, calculés par le même chemin que la purge :
        // un gain affiché qui divergerait de ce qui part serait un mensonge.
        let entries = [e("a", "M", day: 3, mb: 10), e("b", "M", day: 2, mb: 7),
                       e("c", "M", day: 1, mb: 5)]
        let report = MaintenanceInventory.Report(
            backups: entries, protections: [:],
            configBackupCount: 0, configBackupBytes: 0,
            orphanSessions: [], stalePreferenceKeys: [])
        #expect(report.freedBytes(keepPerMod: 1) == 12_000_000)
        #expect(report.freedBytes(keepPerMod: 3) == 0)
    }

    @Test func anEmptyReportIsSilentRatherThanZeroed() {
        // Ce que l'écran doit distinguer : « rien à faire » et « pas encore
        // mesuré » ne s'affichent pas pareil.
        let report = MaintenanceInventory.Report(
            backups: [], protections: [:], configBackupCount: 0, configBackupBytes: 0,
            orphanSessions: [], stalePreferenceKeys: [])
        #expect(report.isEmpty)
        #expect(report.totalBytes == 0)
    }
}
