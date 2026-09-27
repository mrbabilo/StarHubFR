import Foundation
import Testing
@testable import StarHubTHCore

struct ModHistoryTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func entry(_ kind: ModHistory.Kind, to version: String?,
                       files: [String: String]) -> ModHistory.Entry {
        ModHistory.Entry(date: Date(timeIntervalSince1970: 1_790_000_000), kind: kind,
                         fromVersion: nil, toVersion: version, archiveSHA256: nil,
                         nexusFileId: nil, source: nil,
                         files: files.map { .init(path: $0.key, size: 1, sha256: $0.value) },
                         report: nil)
    }

    @Test func appendsAndReadsBack() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(ModHistoryFile.load(uniqueId: "a.mod", directory: directory) == .missing)
        try ModHistoryFile.append(entry(.install, to: "1.0.0", files: ["A.png": "x"]),
                                  uniqueId: "a.mod", directory: directory)
        try ModHistoryFile.append(entry(.update, to: "1.1.0", files: ["A.png": "y"]),
                                  uniqueId: "a.mod", directory: directory)
        let history = ModHistoryFile.history(uniqueId: "a.mod", directory: directory)
        #expect(history.entries.map(\.kind) == [.install, .update])
        #expect(history.authorVersions.map(\.version) == ["1.0.0", "1.1.0"])
        #expect(history.authorVersions.last?.files == ["a.png": "y"])
    }

    /// Un journal abîmé n'efface pas l'historique : il est mis de côté.
    @Test func anUnreadableHistoryIsSetAsideNotOverwritten() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{".utf8).write(to: directory.appendingPathComponent("a.mod.json"))
        #expect(ModHistoryFile.load(uniqueId: "a.mod", directory: directory) == .unreadable)
        try ModHistoryFile.append(entry(.install, to: "1.0.0", files: [:]), uniqueId: "a.mod",
                                  directory: directory, now: Date(timeIntervalSince1970: 42))
        let aside = directory.appendingPathComponent("a.mod.unreadable-42.json")
        #expect(FileManager.default.contents(atPath: aside.path) == Data("{".utf8))
        #expect(ModHistoryFile.history(uniqueId: "a.mod", directory: directory).entries.count == 1)
    }

    @Test func additionsAreDepositsNotVersions() {
        var history = ModHistory(uniqueId: "a.mod")
        history.append(entry(.addition, to: nil, files: ["i18n/FR.json": "t"]))
        #expect(history.depositedKeys == ["i18n/fr.json"])
        #expect(history.authorVersions.isEmpty)
    }

    /// Un rapport d'une version future (champ inconnu) ou passée (champ
    /// manquant) se lit : sinon le journal entier passerait pour illisible.
    @Test func reportsDecodeWithMissingOrExtraFields() throws {
        let json = #"{"removedGhosts":["a.png"],"somethingNew":true}"#
        let report = try JSONDecoder().decode(UpdateTriageReport.self, from: Data(json.utf8))
        #expect(report.removedGhosts == ["a.png"])
        #expect(report.keptLocal.isEmpty)
    }
}
