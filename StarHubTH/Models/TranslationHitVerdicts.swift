import Foundation

/// P5-4 (audit UX 2026-10-16) — les résultats de traduction Nexus que
/// l'utilisateur a écartés : « Ce n'est pas la bonne ». La recherche par nom
/// se trompe une fois sur trois (4 fausses sur 11 mesurées, C5-T1), et sans
/// ce geste le même faux revenait à chaque balayage, en tête de page.
///
/// Le cache du balayage garde l'observation brute ; l'écart se lit **au
/// statut** (`FrenchTranslationSweep.status`), jamais au cache : un
/// re-balayage total ne fait pas revenir un écarté. La clé est le dossier
/// logique du mod et l'identifiant Nexus du résultat — un résultat renommé
/// par son auteur reste écarté, ce qui est voulu.
public struct TranslationHitVerdicts: Codable, Equatable, Sendable {

    /// Un résultat écarté. Le nom du résultat et celui du mod sont retenus
    /// pour la liste « Écartés » : le mod a pu être désinstallé depuis.
    public struct Dismissal: Codable, Equatable, Sendable, Identifiable {
        public let folderName: String
        public let modName: String
        public let hitModId: Int
        public let hitName: String
        public let dismissedAt: Date
        public var id: String { "\(folderName)|\(hitModId)" }
    }

    /// Les plus récents d'abord : la liste « Écartés » sert surtout à
    /// rattraper le clic qu'on vient de faire.
    public private(set) var dismissals: [Dismissal] = []

    public init() {}

    /// Les résultats écartés pour ce mod, par identifiant Nexus.
    public func dismissedModIds(for folderName: String) -> Set<Int> {
        Set(dismissals.filter { $0.folderName == folderName }.map(\.hitModId))
    }

    /// Écarter deux fois ne double rien : le second geste rafraîchit la date.
    public mutating func dismiss(_ hit: NexusModSearch.Hit, for folderName: String,
                                 modName: String, at date: Date) {
        dismissals.removeAll { $0.folderName == folderName && $0.hitModId == hit.modId }
        dismissals.insert(Dismissal(folderName: folderName, modName: modName, hitModId: hit.modId,
                                    hitName: hit.name, dismissedAt: date), at: 0)
    }

    public mutating func restore(_ dismissal: Dismissal) {
        dismissals.removeAll { $0.id == dismissal.id }
    }

    // MARK: - Disque

    /// Une trace de l'utilisateur, pas un cache : dans Application Support,
    /// comme `ModConflictVerdictsStore`. Absent ou illisible : vide, sans
    /// empêcher la page de s'ouvrir.
    public enum Storage {
        static var fileURL: URL? {
            AppSupport.directory?.appendingPathComponent("translation_hit_verdicts.json")
        }

        public static func load(from url: URL? = nil) -> TranslationHitVerdicts {
            guard let target = url ?? fileURL else { return TranslationHitVerdicts() }
            do {
                return try JSONDecoder().decode(TranslationHitVerdicts.self, from: Data(contentsOf: target))
            } catch {
                return TranslationHitVerdicts()
            }
        }

        /// `false` en cas d'échec, que l'appelant doit dire : un écart perdu
        /// en silence ferait revenir le faux au prochain lancement.
        @discardableResult
        public static func save(_ verdicts: TranslationHitVerdicts, to url: URL? = nil) -> Bool {
            guard let target = url ?? fileURL else { return false }
            do {
                let data = try JSONEncoder().encode(verdicts)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }
}
