import Foundation

/// Builds a mod's dependency list from its parsed manifest JSON, merging the
/// two ways SMAPI expresses dependencies:
///   • `Dependencies` — an array of `{ UniqueID, IsRequired }` objects.
///   • `ContentPackFor` — a single `{ UniqueID }` object naming the framework a
///     content pack targets. This is a HARD requirement and, crucially, is how
///     most content packs (a large share of installed mods) declare their only
///     dependency — so ignoring it (as the old inline parse did) made those
///     mods look dependency-free. Mesuré sur le parc (1 085 manifests) : **625
///     déclarent un `ContentPackFor`**, dont 254 sans aucune autre dépendance.
/// Entries are de-duplicated by case-insensitive `UniqueID`; if the same id is
/// seen as both optional and required, the required flag wins.
enum ModDependencyParser {
    static func parse(manifest json: [String: Any]) -> [ModDependency] {
        var result: [ModDependency] = []

        func add(_ rawId: String, required: Bool, minimum: String?) {
            let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }
            let key = id.lowercased()
            if let idx = result.firstIndex(where: { $0.uniqueId.lowercased() == key }) {
                // Déclarée deux fois : requise l'emporte, la plus haute version
                // minimale aussi — c'est celle que SMAPI fera respecter.
                result[idx] = ModDependency(uniqueId: result[idx].uniqueId,
                                            isRequired: required || result[idx].isRequired,
                                            minimumVersion: higherMinimum(result[idx].minimumVersion, minimum))
                return
            }
            result.append(ModDependency(uniqueId: id, isRequired: required, minimumVersion: minimum))
        }

        if let deps = json.caseInsensitiveValue(forKey: "Dependencies") as? [[String: Any]] {
            for dep in deps {
                if let depId = dep.caseInsensitiveValue(forKey: "UniqueID") as? String {
                    add(depId, required: isRequired(dep.caseInsensitiveValue(forKey: "IsRequired")),
                        minimum: minimumVersion(dep.caseInsensitiveValue(forKey: "MinimumVersion")))
                }
            }
        }
        if let cpf = json.caseInsensitiveValue(forKey: "ContentPackFor") as? [String: Any],
           let cpfId = cpf.caseInsensitiveValue(forKey: "UniqueID") as? String {
            add(cpfId, required: true, minimum: minimumVersion(cpf.caseInsensitiveValue(forKey: "MinimumVersion")))
        }
        return result
    }

    /// `MinimumVersion` en texte (`"0.6.4-unofficial-mushymato.0"`) ; vide,
    /// absent ou d'un autre type : pas d'exigence.
    static func minimumVersion(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// La plus exigeante de deux versions minimales (`nil` : aucune).
    static func higherMinimum(_ a: String?, _ b: String?) -> String? {
        guard let a else { return b }
        guard let b else { return a }
        return NexusUpdateChecker.compare(a, b) == .orderedAscending ? b : a
    }

    /// `IsRequired` tel que SMAPI le lit (Newtonsoft) : un booléen, ou un
    /// texte « true »/« false » quelle que soit la casse. Mesuré sur le parc
    /// (2026-10-02) : 11 `"false"` en texte, dont 9 dans *Vanilla Tweaks -
    /// Interface* — lus comme requis, ils affichaient 9 dépendances manquantes
    /// qu'aucun mod n'exige. Absent ou illisible : requis, le défaut de SMAPI.
    static func isRequired(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "false": return false
            case "true": return true
            default: break
            }
        }
        return true
    }
}
