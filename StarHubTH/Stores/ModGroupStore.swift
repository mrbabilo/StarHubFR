import Foundation
import Observation

/// I-T21 lot 2 — les groupes, persistés dans `mod_groups.json`. Un fichier
/// illisible n'est **jamais** écrasé : il est mis de côté, l'état repart vide
/// et le journal le dit (un cache d'octets étrangers se décode d'abord).
@MainActor
@Observable
final class ModGroupStore {
    static let fileName = "mod_groups.json"

    private(set) var state: ModGroupsState
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let log: (String) -> Void
    /// Faux quand un fichier illisible n'a pas pu être mis de côté : écrire
    /// l'écraserait.
    @ObservationIgnored private var writable = true

    init(directory: URL?, log: @escaping (String) -> Void = { _ in }) {
        self.fileURL = directory?.appendingPathComponent(Self.fileName)
        self.log = log
        let loaded = Self.load(fileURL, log: log)
        self.state = loaded.state
        self.writable = loaded.writable
    }

    /// Faux sans dossier, ou quand un fichier illisible est resté en place.
    var canPersist: Bool { fileURL != nil && writable }

    func update(_ change: (inout ModGroupsState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        persist()
    }

    private func persist() {
        guard let fileURL, writable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            log("Groupes de mods non enregistrés : \(error.localizedDescription)")
        }
    }

    private static func load(_ url: URL?, log: (String) -> Void) -> (state: ModGroupsState, writable: Bool) {
        // Présent mais illisible (droits, erreur d'E/S) n'est pas absent :
        // `contents(atPath:)` rendrait nil, et l'écriture suivante l'écraserait.
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return (ModGroupsState(), true) }
        do {
            return (try JSONDecoder().decode(ModGroupsState.self, from: try Data(contentsOf: url)), true)
        } catch let future as ModGroupsState.FutureFormat {
            // Laissé en place, intact, pour la version qui l'a écrit.
            log("Groupes de mods d'un format plus récent (\(future.version)), laissés en place : changements non enregistrés.")
            return (ModGroupsState(), false)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(fileName).unreadable-\(stamp)")
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                log("Groupes de mods illisibles, mis de côté : \(aside.lastPathComponent)")
                return (ModGroupsState(), true)
            } catch {
                log("Groupes de mods illisibles, laissés en place : \(error.localizedDescription)")
                return (ModGroupsState(), false)
            }
        }
    }
}
