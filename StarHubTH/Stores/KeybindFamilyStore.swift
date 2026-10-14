import Foundation
import Observation

/// Plan de raccourcis — les corrections de famille de touches faites par
/// l'utilisateur, persistées dans `keybind_families.json`. Même patron que
/// `ModGroupStore` : un fichier illisible est mis de côté, jamais écrasé ; un
/// format plus récent reste intact et l'état en lecture seule.
@MainActor
@Observable
final class KeybindFamilyStore {
    static let fileName = "keybind_families.json"

    private(set) var families: [String: KeybindFamily]
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private var writable = true

    init(directory: URL?, log: @escaping (String) -> Void = { _ in }) {
        self.fileURL = directory?.appendingPathComponent(Self.fileName)
        self.log = log
        let loaded = Self.load(fileURL, log: log)
        self.families = loaded.file.families
        self.writable = loaded.writable
    }

    /// Faux sans dossier, ou quand le fichier est resté en place (illisible ou plus récent).
    var canPersist: Bool { fileURL != nil && writable }

    /// `nil` retire la correction.
    func set(_ family: KeybindFamily?, for folderName: String) {
        var next = families
        next[folderName] = family
        guard next != families else { return }
        families = next
        persist()
    }

    private func persist() {
        guard let fileURL, writable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(KeybindFamilyFile(families: families)).write(to: fileURL, options: .atomic)
        } catch {
            log("Familles de raccourcis non enregistrées : \(error.localizedDescription)")
        }
    }

    private static func load(_ url: URL?, log: (String) -> Void) -> (file: KeybindFamilyFile, writable: Bool) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return (KeybindFamilyFile(), true) }
        do {
            return (try JSONDecoder().decode(KeybindFamilyFile.self, from: try Data(contentsOf: url)), true)
        } catch let future as KeybindFamilyFile.FutureFormat {
            log("Familles de raccourcis d'un format plus récent (\(future.version)), laissées en place : changements non enregistrés.")
            return (KeybindFamilyFile(), false)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(fileName).unreadable-\(stamp)")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                log("Familles de raccourcis illisibles, mises de côté : \(aside.lastPathComponent)")
                return (KeybindFamilyFile(), true)
            } catch {
                log("Familles de raccourcis illisibles, laissées en place : \(error.localizedDescription)")
                return (KeybindFamilyFile(), false)
            }
        }
    }
}
