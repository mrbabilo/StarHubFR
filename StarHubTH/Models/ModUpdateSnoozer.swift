import Foundation

/// R3 — un update Nexus mis en veille (« snooze ») : il quitte la liste
/// « updates » sans être masqué dans l'inventaire, et l'entrée **expire
/// toute seule**.
///
/// L'identité d'un snooze est l'`UniqueID` du mod — jamais l'identifiant
/// Nexus (58 id partagés sur le parc réel) ni le nom de dossier (un
/// renommage de dossier ne doit pas réveiller un snooze).
///
/// Trois modes d'expiration :
/// - `.oneWeek` : horloge, sept jours ;
/// - `.untilModVersion` : la version que Nexus annonce au moment du snooze
///   est mémorisée ; une version **différente** réveille l'update. Des mois
///   plus tard, la même version affichée garde le snooze ;
/// - `.untilGameVersion` : la version **locale** du jeu (journal SMAPI) est
///   mémorisée ; le passage du jeu à une autre version réveille l'update —
///   c'est le mode « cet update ne m'intéresse que pour la prochaine
///   version de Stardew ».
///
/// Absence d'information (version lue `nil`) : le snooze tient — on ne
/// réveille pas le bruit sur une absence, seulement sur un changement.
public struct ModUpdateSnoozeEntry: Codable, Equatable {
    public enum Mode: String, Codable {
        case oneWeek
        case untilModVersion
        case untilGameVersion
    }

    public let uniqueId: String
    public let mode: Mode
    public let snoozedAt: Date
    /// Version annoncée par Nexus au moment du snooze (mode
    /// `.untilModVersion`).
    public let modVersionAtSnooze: String?
    /// Version locale du jeu au moment du snooze (mode `.untilGameVersion`).
    public let gameVersionAtSnooze: String?

    /// Date de fin d'un snooze horloge, `nil` pour les modes événementiels
    /// — eux expirent sur un changement de version, pas sur une horloge.
    public var expiresAt: Date? {
        mode == .oneWeek ? snoozedAt.addingTimeInterval(ModUpdateSnoozer.oneWeekInterval) : nil
    }
}

/// Store des snoozes. Persistance plate en `UserDefaults` (JSON encodé) :
/// une donnée légère dont la perte n'est pas critique — un snooze perdu ne
/// fait que réapparaître l'update, jamais masquer une information.
///
/// L'expiration est **paresseuse** : évaluée (et purgée) au moment où l'on
/// interroge, pas sur un minuteur. Tout appel vient du fil principal.
public final class ModUpdateSnoozer {
    /// Largeur du mode `.oneWeek`.
    public static let oneWeekInterval: TimeInterval = 7 * 86_400
    /// Clé du store — exposée pour les tests, qui écrivent un état corrompu
    /// directement.
    public static let storeKey = "modUpdateSnoozes"

    /// Le `UserDefaults` injecté — interne, pour les tests de persistance.
    let defaultsForTesting: UserDefaults
    private let defaults: UserDefaults
    private var entries: [String: ModUpdateSnoozeEntry]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaultsForTesting = defaults
        // Store illisible (corruption, encodage d'une autre version) : on
        // démarre vide plutôt que de crasher — le défaut est cosmétique.
        if let data = defaults.data(forKey: Self.storeKey) {
            do {
                entries = try JSONDecoder().decode([String: ModUpdateSnoozeEntry].self, from: data)
            } catch {
                print("Warning: mod update snooze store undecodable: \(error)")
                entries = [:]
            }
        } else {
            entries = [:]
        }
    }

    /// Pose ou remplace le snooze d'un mod, en mémorisant les versions vues
    /// au moment du geste.
    public func snooze(uniqueId: String, mode: ModUpdateSnoozeEntry.Mode,
                       currentModVersion: String?, currentGameVersion: String?,
                       now: Date = Date()) {
        entries[uniqueId] = ModUpdateSnoozeEntry(
            uniqueId: uniqueId, mode: mode, snoozedAt: now,
            modVersionAtSnooze: currentModVersion,
            gameVersionAtSnooze: currentGameVersion
        )
        persist()
    }

    /// Réveille explicitement (bouton « réactiver » de l'UI).
    public func clear(uniqueId: String) {
        guard entries.removeValue(forKey: uniqueId) != nil else { return }
        persist()
    }

    /// L'entrée encore vivante pour ce mod, si elle existe — pour l'affichage
    /// du motif et de l'échéance. Ne purge rien.
    public func entry(for uniqueId: String) -> ModUpdateSnoozeEntry? {
        entries[uniqueId]
    }

    /// Le mod est-il encore en veille ? Les entrées expirées sont purgées au
    /// passage : le store rétrécit tout seul à l'usage.
    public func isSnoozed(uniqueId: String, currentModVersion: String?,
                          currentGameVersion: String?, now: Date = Date()) -> Bool {
        guard let entry = entries[uniqueId] else { return false }
        if isExpired(entry, currentModVersion: currentModVersion,
                     currentGameVersion: currentGameVersion, now: now) {
            entries.removeValue(forKey: uniqueId)
            persist()
            return false
        }
        return true
    }

    private func isExpired(_ entry: ModUpdateSnoozeEntry,
                           currentModVersion: String?, currentGameVersion: String?,
                           now: Date) -> Bool {
        switch entry.mode {
        case .oneWeek:
            return now >= entry.expiresAt!
        case .untilModVersion:
            // `nil` = pas de version lue : rien n'a changé de observable.
            guard let current = currentModVersion else { return false }
            return current != entry.modVersionAtSnooze
        case .untilGameVersion:
            guard let current = currentGameVersion else { return false }
            return current != entry.gameVersionAtSnooze
        }
    }

    private func persist() {
        // Un échec d'écriture ne mérite pas d'interrompre le geste : le
        // snooze tient en mémoire pour la session, et repartira au suivant.
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Self.storeKey)
        } catch {
            print("Warning: mod update snooze store write failed: \(error)")
        }
    }
}
