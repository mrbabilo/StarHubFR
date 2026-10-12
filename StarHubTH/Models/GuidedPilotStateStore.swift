import Foundation

/// `guided-pilot-state.json` : l'état du pilotage sur disque, pour reprendre
/// ou annuler après un plantage de l'app (spec P1 §7). Dossier injecté sans
/// valeur par défaut — la production passe `AppSupport.directory`, les tests
/// un dossier temporaire. Patron `BenchmarkSnapshotStore`.
public enum GuidedPilotStateStore {
    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("guided-pilot-state.json")
    }

    /// Faux si l'état n'a pas pu être écrit : l'appelant n'annonce pas un
    /// pilotage « reprise possible » sans filet sur disque.
    @discardableResult
    public static func save(_ plan: GuidedPilotPlan, in directory: URL?) -> Bool {
        guard let directory else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(plan).write(to: fileURL(in: directory), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func load(from directory: URL?) -> GuidedPilotPlan? {
        guard let directory,
              let data = FileManager.default.contents(atPath: fileURL(in: directory).path)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GuidedPilotPlan.self, from: data)
    }

    public static func hasPending(in directory: URL?) -> Bool {
        guard let directory else { return false }
        return FileManager.default.fileExists(atPath: fileURL(in: directory).path)
    }

    @discardableResult
    public static func clear(in directory: URL?) -> Bool {
        guard let directory else { return true }
        let url = fileURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
