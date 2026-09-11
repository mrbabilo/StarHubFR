import Foundation

/// C2-T4 §8.2 — appliquer des renommages aux fichiers de l'utilisateur, en
/// logique pure pour être testée. Jamais d'écrasement d'une valeur déjà
/// posée : l'abstention est par paire, une paire refusée n'empêche pas les
/// autres.
public enum RenameReport {

    /// Reporte des paires dans un texte de `fr.json` : la nouvelle clé prend
    /// la position de l'ancienne, l'ancienne disparaît. Abstention par paire
    /// si la nouvelle clé est déjà traduite (on n'écrase jamais) ou si
    /// l'ancienne n'a rien à sauver. Rend le texte réécrit et les paires
    /// réellement appliquées — texte intact et lot vide si rien ne passe.
    public static func applyToFrench(_ text: String,
                                     pairs: [RenamePair]) -> (text: String, applied: [RenamePair]) {
        guard let values = try? JSONSerialization.jsonObject(
            with: Data(text.utf8)) as? [String: String] else { return (text, []) }
        let outline = I18nOutline.read(text)

        var newValues = values
        var applied: [RenamePair] = []
        for pair in pairs {
            guard let frenchValue = values[pair.oldKey] else { continue }   // rien à sauver
            guard newValues[pair.newKey] == nil else { continue }           // déjà traduit
            newValues.removeValue(forKey: pair.oldKey)
            newValues[pair.newKey] = frenchValue
            applied.append(pair)
        }
        guard !applied.isEmpty else { return (text, []) }

        // La nouvelle clé prend la position de l'ancienne ; les clés neuves
        // sans ancêtre vont en fin.
        var ordered: [String] = []
        for key in outline.orderedKeys {
            if let replacement = applied.first(where: { $0.oldKey == key })?.newKey {
                if !ordered.contains(replacement) { ordered.append(replacement) }
            } else if newValues[key] != nil && !ordered.contains(key) {
                ordered.append(key)
            }
        }
        for key in newValues.keys.sorted() where !ordered.contains(key) { ordered.append(key) }

        guard let rewritten = try? OrderedJSONWriter.text(orderedKeys: ordered, values: newValues)
        else { return (text, []) }
        return (rewritten, applied)
    }
    /// Un fichier d'une locale, identifié par ce que l'appelant saura
    /// retrouver — un nom de fichier, un chemin.
    public struct FrenchFile: Equatable, Sendable {
        public let id: String
        public let text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    /// Ce qu'un report a produit sur un fichier — et seuls les fichiers
    /// **réellement modifiés** en portent un. Réécrire les autres serait du
    /// travail pour rien, et chaque écriture dans un dossier de mod en ouvre
    /// les droits (X7).
    public struct FileRewrite: Equatable, Sendable {
        public let id: String
        public let text: String
        /// Les paires appliquées **dans ce fichier**. La ventilation compte :
        /// l'appelant écrit fichier par fichier, et une écriture qui échoue
        /// ne doit retirer du bilan que ses propres paires.
        public let applied: [RenamePair]
    }

    /// Ce qu'un report a produit sur un ensemble de fichiers, dans l'ordre où
    /// ils ont été traités.
    public struct Spread: Equatable, Sendable {
        public let files: [FileRewrite]

        public var applied: [RenamePair] { files.flatMap(\.applied) }
    }

    public static func applyToFrenchFiles(_ files: [FrenchFile],
                                          pairs: [RenamePair]) -> Spread {
        var remaining = pairs
        var rewrites: [FileRewrite] = []
        for file in files {
            guard !remaining.isEmpty else { break }
            let outcome = applyToFrench(file.text, pairs: remaining)
            guard !outcome.applied.isEmpty else { continue }
            rewrites.append(FileRewrite(id: file.id, text: outcome.text,
                                        applied: outcome.applied))
            let done = Set(outcome.applied)
            remaining.removeAll { done.contains($0) }
        }
        return Spread(files: rewrites)
    }
}

extension RenameReport {

    /// Reporte des paires de clés de premier niveau dans un `config.json`.
    /// Les valeurs non-chaîne (booléens, nombres, objets imbriqués des mods
    /// C#) passent telles quelles. Abstention par paire si la nouvelle clé
    /// existe déjà. Réécriture JSONSerialization : l'ordre n'est pas
    /// préservé — le jeu réécrit ce fichier lui-même à chaque lancement.
    public static func applyToConfig(_ text: String,
                                     pairs: [RenamePair]) -> (text: String, applied: [RenamePair]) {
        guard var obj = try? JSONSerialization.jsonObject(
            with: Data(text.utf8)) as? [String: Any] else { return (text, []) }

        var applied: [RenamePair] = []
        for pair in pairs {
            guard let value = obj[pair.oldKey] else { continue }   // rien à reporter
            guard obj[pair.newKey] == nil else { continue }        // la cible existe
            obj.removeValue(forKey: pair.oldKey)
            obj[pair.newKey] = value
            applied.append(pair)
        }
        guard !applied.isEmpty else { return (text, []) }

        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let rewritten = String(data: data, encoding: .utf8)
        else { return (text, []) }
        return (rewritten, applied)
    }

    // MARK: - Routage par composant (revue C2-T4 n°6/n°9)

    /// Sépare `"Composant/clé"` en (composant, clé) sur le plus long préfixe
    /// de composants connu ; sans préfixe connu, tout est la clé (racine).
    /// Une clé i18n peut elle-même contenir un `/` (packs Content Patcher :
    /// `"Strings/…"`) — d'où le plus long préfixe, jamais le premier.
    public static func splitQualifiedKey(_ qualified: String,
                                         known prefixes: [String]) -> (String, String) {
        let match = prefixes.filter { !$0.isEmpty }
            .filter { qualified.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
        if let m = match {
            return (m, String(qualified.dropFirst(m.count + 1)))
        }
        return ("", qualified)
    }

    /// Une paire routée : telle qu'affichée (clés qualifiées) et telle que le
    /// `fr.json` du composant doit la voir (clés brutes).
    public struct RoutedPair: Equatable {
        public let pair: RenamePair
        public let raw: RenamePair

        public init(pair: RenamePair, raw: RenamePair) {
            self.pair = pair
            self.raw = raw
        }
    }

    /// La destination de chaque paire : le composant de son ANCIENNE clé,
    /// à condition que la nouvelle vive sous le même. Un renommage qui
    /// CHANGE de composant (composant entier rebaptisé, paire par valeur à
    /// travers le pack) n'est pas reportable : le `fr.json` de l'ancien
    /// composant n'a pas de clé à remplacer — y écrire la forme brute de la
    /// nouvelle clé y déposerait une orpheline pendant que la vraie restera
    /// non traduite, et la paire passerait « réconciliée » sans un mot. Ces
    /// paires sont rendues à part : l'écran les annonce, l'onglet diff
    /// reste l'outil. Une nouvelle clé sous un composant inconnu du scan
    /// compte comme cross — on ne sait pas quel fichier viser.
    public static func routeByOldComponent(_ pairs: [RenamePair],
                                           known prefixes: [String])
        -> (byComponent: [String: [RoutedPair]], crossComponent: [RenamePair]) {
        var byComponent: [String: [RoutedPair]] = [:]
        var crossComponent: [RenamePair] = []
        for pair in pairs {
            let (oldComponent, oldRaw) = splitQualifiedKey(pair.oldKey, known: prefixes)
            let (newComponent, newRaw) = splitQualifiedKey(pair.newKey, known: prefixes)
            guard oldComponent == newComponent else {
                crossComponent.append(pair)
                continue
            }
            byComponent[oldComponent, default: []]
                .append(RoutedPair(pair: pair,
                                   raw: RenamePair(oldKey: oldRaw, newKey: newRaw)))
        }
        return (byComponent, crossComponent)
    }
}
