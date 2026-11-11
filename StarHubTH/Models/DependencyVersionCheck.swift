import Foundation

/// Une archive qu'on s'apprête à installer contient-elle un mod **trop ancien**
/// pour les mods actifs qui en dépendent ?
///
/// Cas réel du parc (relevé des sources du 2026-11-11) : StardewUI installé est
/// le fork `0.6.4-unofficial-mushymato.1` (page Nexus 43861), qui garde
/// l'`UniqueID` de l'original. L'annuaire des dépendances mène à la page de
/// l'original (28870), dont le dernier fichier principal est la 0.6.1, alors que
/// Livestock Bazaar et Machine Control Panel exigent au moins une 0.6.3/0.6.4
/// « unofficial ». Installée, cette 0.6.1 ferait refuser les deux par SMAPI —
/// et l'app ne lisait pas `MinimumVersion`. Idée signalée par JuniGrid 1.3.1
/// (StardewUI Continued) ; rien de son code n'est repris.
///
/// Jugée sur l'archive elle-même, la garde vaut quel que soit son chemin :
/// dépendance manquante, lien `nxm://`, glisser-déposer, mise à jour. Seules les
/// dépendances **requises** des mods **actifs** comptent — comme
/// `MissingDependencies.plan` — et un mod livré dans la même archive n'exige
/// rien : il sera remplacé avec elle.
public enum DependencyVersionCheck {
    public struct Unmet: Identifiable, Equatable, Sendable {
        public let uniqueId: String
        /// Le nom du mod tel que l'archive le livre.
        public let name: String
        public let found: String
        public let required: String
        /// Le mod actif qui exige la version la plus haute.
        public let requiredBy: String
        public var id: String { uniqueId.lowercased() }
    }

    public static func unmet(detected: [(uniqueId: String, name: String, version: String)],
                             mods: [ModItem]) -> [Unmet] {
        let shipped = Set(detected.map { $0.uniqueId.lowercased() })
        // UniqueID requis → (version la plus haute, mod qui l'exige).
        var demands: [String: (version: String, by: String)] = [:]
        for top in mods where top.isEnabled {
            for mod in top.components where mod.isEnabled && !shipped.contains(mod.uniqueId.lowercased()) {
                for dep in mod.dependencies where dep.isRequired {
                    guard let minimum = dep.minimumVersion else { continue }
                    let key = dep.uniqueId.lowercased()
                    if let current = demands[key],
                       NexusUpdateChecker.compare(minimum, current.version) != .orderedDescending { continue }
                    demands[key] = (minimum, mod.name)
                }
            }
        }
        return detected.compactMap { mod in
            let version = mod.version.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, let demand = demands[mod.uniqueId.lowercased()],
                  NexusUpdateChecker.compare(version, demand.version) == .orderedAscending else { return nil }
            return Unmet(uniqueId: mod.uniqueId, name: mod.name, found: version,
                         required: demand.version, requiredBy: demand.by)
        }
    }
}
