import Foundation

/// A2-T5 — le troisième filet de compatibilité, **local et sans réseau** :
/// `smapi-internal/metadata.json`, le fichier que SMAPI embarque pour ses
/// propres contrôles (volet `ModData` : 188 entrées au 2026-10-07).
///
/// ⚠️ **La clause de version n'est pas un détail** : chaque champ y vit sous
/// une clé `"<borne> | Status"` qui ne s'applique que si la version installée
/// est **strictement inférieure** à la borne (`~1.13.11` : en dessous de
/// 1.13.11). Mesuré sur le parc de l'auteur : 17 manifestes couverts, **0**
/// signal réel — et **14 faux positifs** si les bornes sont ignorées (SVE
/// 1.15.11, Json Assets 1.11.11, Shop Tile Framework 1.0.13…). Ce rapport,
/// pas la difficulté, fixait la priorité de la case. Une version installée
/// vide ou illisible laisse la clause muette : ne rien affirmer plutôt que
/// signaler un mod sain.
///
/// Hiérarchie des sources : smapi.io (live, le plus riche) > dump Pathoschild
/// (6 h) > ce fichier (toujours là dès que SMAPI est installé). Il ne remplit
/// que les verdicts encore inconnus.
public enum SmapiLocalMetadata {

    /// Une entrée `ModData` réduite à ses clauses Status et raisons.
    public struct Entry: Sendable {
        /// `("~1.13.11", valeur)` — la borne vide `"~"` s'applique toujours.
        public let statusClauses: [(bound: String, value: String)]
        public let reasonPhrases: [String]
        public let reasonDetails: [String]

        /// Le statut qui s'applique à `installedVersion`, ou `nil`. Clause
        /// bornée + version illisible = muet ; statut hors
        /// `AssumeBroken`/`Obsolete`/`OK` (format inconnu) = muet.
        public func status(installedVersion: String) -> ModCompatibility.Status? {
            for (bound, raw) in statusClauses {
                let ceiling = bound.dropFirst()
                if !ceiling.isEmpty {
                    guard !installedVersion.isEmpty,
                          !CompatibilityResolution.isAtLeast(installedVersion, String(ceiling))
                    else { continue }
                }
                switch raw {
                case "AssumeBroken": return .broken
                case "Obsolete": return .obsolete
                case "OK": return .ok
                default: continue
                }
            }
            return nil
        }
    }

    /// Indexe `ModData` par `Id` plié. JSONC (commentaires, virgules
    /// traînantes) par le parseur commun ; une section absente ou illisible
    /// rend un index vide — le fichier appartient à SMAPI, pas à nous.
    public static func parse(_ text: String) -> [String: Entry] {
        guard let root = I18nLenientParser.lenientObject(text),
              let modData = root["ModData"] as? [String: Any] else { return [:] }
        var index: [String: Entry] = [:]
        for (_, raw) in modData {
            guard let fields = raw as? [String: Any],
                  let id = fields["Id"] as? String, !id.isEmpty else { continue }
            var clauses: [(String, String)] = []
            var phrases: [String] = []
            var details: [String] = []
            for (key, value) in fields {
                // `"<borne> | <champ>"` : la borne est `~`, `~1.13.11` ou
                // `Default` (UpdateKey sans clause — pas notre affaire).
                guard let bar = key.firstIndex(of: "|"),
                      value is String, key.hasPrefix("~") else { continue }
                let bound = key[..<bar].trimmingCharacters(in: .whitespaces)
                let field = key[key.index(after: bar)...].trimmingCharacters(in: .whitespaces)
                let text = value as? String ?? ""
                switch field {
                case "Status": clauses.append((bound, text))
                case "StatusReasonPhrase" where !text.isEmpty: phrases.append(text)
                case "StatusReasonDetails" where !text.isEmpty: details.append(text)
                default: break
                }
            }
            guard !clauses.isEmpty else { continue }
            index[id.lowercased()] = Entry(statusClauses: clauses, reasonPhrases: phrases,
                                           reasonDetails: details)
        }
        return index
    }

    /// Les verdicts applicables, rendus dans le type commun des trois sources.
    /// La clé est l'`UniqueID` tel que l'appelant l'a écrit.
    public static func verdicts(for installed: [(id: String, version: String)],
                                from index: [String: Entry]) -> [String: ModCompatibility] {
        var verdicts: [String: ModCompatibility] = [:]
        for mod in installed where !mod.id.isEmpty {
            guard let entry = index[mod.id.lowercased()],
                  let status = entry.status(installedVersion: mod.version),
                  status.needsAttention else { continue }
            let summary = (entry.reasonPhrases + entry.reasonDetails).joined(separator: " ")
            verdicts[mod.id] = ModCompatibility(status: status, brokeIn: nil,
                                                summary: summary, links: [])
        }
        return verdicts
    }

    /// Lit `gameDir/smapi-internal/metadata.json` et rend les verdicts
    /// applicables aux mods installés donnés. `nil` : pas de fichier (SMAPI
    /// absent) ou fichier illisible — rien à affirmer.
    public static func loadVerdicts(gameDir: String, mods: [ModItem],
                                    uniqueIds: [String]) -> [String: ModCompatibility]? {
        guard !gameDir.isEmpty else { return nil }
        let wanted = Set(uniqueIds.filter { !$0.isEmpty })
        let installed = mods.filter { wanted.contains($0.uniqueId) }.map { ($0.uniqueId, $0.version) }
        let path = (gameDir as NSString).appendingPathComponent("smapi-internal/metadata.json")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let verdicts = Self.verdicts(for: installed, from: Self.parse(text))
        return verdicts.isEmpty ? nil : verdicts
    }

    /// `fresh` ne remplit que les inconnus de `existing` — les deux autres
    /// sources priment. `nil` si rien à ajouter.
    public static func fillBlanks(_ fresh: [String: ModCompatibility],
                                  into existing: [String: ModCompatibility]) -> [String: ModCompatibility]? {
        var merged = existing
        var added = false
        for (id, verdict) in fresh where merged[id] == nil { merged[id] = verdict; added = true }
        return added ? merged : nil
    }

    /// Le miroir du piège : ce que dirait le parseur **sans** lire les bornes.
    /// Utilisé par le test qui compte les 14 faux positifs — jamais en app.
    public static func statusIgnoringBounds(for id: String, in index: [String: Entry]) -> ModCompatibility.Status? {
        guard let entry = index[id.lowercased()] else { return nil }
        return entry.statusClauses.first { $0.value != "OK" }.map { raw in
            raw.value == "Obsolete" ? ModCompatibility.Status.obsolete : .broken
        }
    }
}
