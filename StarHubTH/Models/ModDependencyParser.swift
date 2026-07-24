import Foundation

/// Builds a mod's dependency list from its parsed manifest JSON, merging the
/// two ways SMAPI expresses dependencies:
///   • `Dependencies` — an array of `{ UniqueID, IsRequired }` objects.
///   • `ContentPackFor` — a single `{ UniqueID }` object naming the framework a
///     content pack targets. This is a HARD requirement and, crucially, is how
///     most content packs (a large share of installed mods) declare their only
///     dependency — so ignoring it (as the old inline parse did) made those
///     mods look dependency-free.
/// Entries are de-duplicated by case-insensitive `UniqueID`; if the same id is
/// seen as both optional and required, the required flag wins.
enum ModDependencyParser {
    static func parse(manifest json: [String: Any]) -> [ModDependency] {
        var result: [ModDependency] = []

        func add(_ rawId: String, required: Bool) {
            let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }
            let key = id.lowercased()
            if let idx = result.firstIndex(where: { $0.uniqueId.lowercased() == key }) {
                if required && !result[idx].isRequired {
                    result[idx] = ModDependency(uniqueId: result[idx].uniqueId, isRequired: true)
                }
                return
            }
            result.append(ModDependency(uniqueId: id, isRequired: required))
        }

        if let deps = json.caseInsensitiveValue(forKey: "Dependencies") as? [[String: Any]] {
            for dep in deps {
                if let depId = dep.caseInsensitiveValue(forKey: "UniqueID") as? String {
                    let isReq = dep.caseInsensitiveValue(forKey: "IsRequired") as? Bool ?? true
                    add(depId, required: isReq)
                }
            }
        }
        if let cpf = json.caseInsensitiveValue(forKey: "ContentPackFor") as? [String: Any],
           let cpfId = cpf.caseInsensitiveValue(forKey: "UniqueID") as? String {
            add(cpfId, required: true)
        }
        return result
    }
}
