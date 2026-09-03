import Foundation

/// Découpe le journal de SMAPI en entrées exploitables.
///
/// Extrait tel quel du ViewModel, où il n'était atteignable par aucun test —
/// alors que c'est lui qui décide **à qui** une erreur est imputée, la question
/// dont dépendent l'historique par mod, la carte de diagnostic et la recherche
/// guidée du mod responsable.
public enum SmapiLogParser {
    /// Format SMAPI : `[HH:MM:SS LEVEL  Context] message`. La double espace
    /// entre le niveau et le contexte est voulue par SMAPI.
    ///
    /// Une ligne sans en-tête est une continuation — typiquement une trace
    /// d'exécution — et rejoint l'entrée précédente plutôt que d'en créer une.
    public static func parse(_ text: String) -> [LogEntry] {
        var entries: [LogEntry] = []

        for line in text.components(separatedBy: .newlines) {
            guard line.hasPrefix("[") else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Une continuation sans entrée à laquelle se rattacher n'a
                // nulle part où aller : la laisser tomber.
                guard !trimmed.isEmpty, !entries.isEmpty else { continue }
                let last = entries.removeLast()
                let combined = last.message.isEmpty ? trimmed : last.message + "\n" + trimmed
                entries.append(LogEntry(timestamp: last.timestamp, message: combined,
                                        level: last.level, source: .smapi,
                                        modName: last.modName))
                continue
            }
            // Crochet ouvrant jamais refermé : ligne tronquée ou corrompue.
            // L'ignorer plutôt que de fabriquer une entrée arbitraire.
            guard let bracketEnd = line.firstIndex(of: "]") else { continue }

            let header = String(line[line.index(after: line.startIndex)..<bracketEnd])
            // Découpage sur les espaces en filtrant les vides : c'est ce qui
            // absorbe la double espace du format.
            let parts = header.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            let timestamp = parts.first ?? "—"
            let level = level(from: parts.count >= 2 ? parts[1] : "")
            let context: String? = {
                guard parts.count >= 3 else { return nil }
                let name = parts[2...].joined(separator: " ")
                // « SMAPI » et « game » sont des sources, pas des mods.
                return (name == "SMAPI" || name == "game") ? nil : name
            }()

            let msgStart = line.index(after: bracketEnd)
            let message = msgStart < line.endIndex
                ? String(line[msgStart...]).trimmingCharacters(in: .whitespaces)
                : ""

            guard !message.isEmpty || context != nil else { continue }

            // SMAPI écrit certaines erreurs **pour le compte** d'un mod : le
            // crochet porte « SMAPI » et le nom du mod n'apparaît qu'en préfixe
            // du message — « [SMAPI] [ERROR] Gunther's Guide: Tried to map… ».
            // Sans cette lecture, ces erreurs n'étaient imputées à personne.
            let modName = context
                ?? ((level == .error || level == .warning)
                    ? LogNoise.modNamePrefix(in: message) : nil)

            entries.append(LogEntry(timestamp: timestamp, message: message,
                                    level: level, source: .smapi, modName: modName))
        }
        return entries
    }

    private static func level(from raw: String) -> LogLevel {
        switch raw.uppercased() {
        case "ERROR": return .error
        // ALERT est une alerte de SMAPI lui-même : même poids qu'un WARN.
        case "WARN", "ALERT": return .warning
        case "INFO": return .info
        // TRACE, DEBUG, et tout ce que SMAPI ajoutera un jour.
        default: return .trace
        }
    }
}

/// Une mise à jour de mod signalée par SMAPI lui-même (hors Nexus).
public struct ModUpdateInfo: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let version: String
    public let url: String

    public init(name: String, version: String, url: String) {
        self.name = name
        self.version = version
        self.url = url
    }
}

extension SmapiLogParser {
    /// Les mises à jour du bloc « You can update N mods: », que SMAPI écrit au
    /// démarrage.
    ///
    /// Une **ligne vide n'interrompt pas le bloc** : le format réel en intercale
    /// une entre chaque entrée, y compris juste après l'en-tête. Traiter toute
    /// ligne sans « ALERT SMAPI » comme la fin du bloc revenait donc à s'arrêter
    /// avant d'avoir lu la moindre entrée — aucune mise à jour n'était jamais
    /// détectée, sans le moindre message. Défaut relevé en amont
    /// (AppleBoiy/StarHubTH, `6306958`) sur un journal réel de 122 000 lignes,
    /// et présent à l'identique ici.
    public static func updates(in text: String) -> [ModUpdateInfo] {
        var updates: [ModUpdateInfo] = []
        var inBlock = false

        for line in text.components(separatedBy: .newlines) {
            if line.contains("You can update") {
                inBlock = true
                continue
            }
            guard inBlock else { continue }

            if line.contains("ALERT SMAPI"), line.contains("https://") {
                // `[12:00:00 ALERT SMAPI]    Content Patcher 2.0.0: https://…`
                let parts = line.components(separatedBy: "ALERT SMAPI]")
                guard parts.count > 1 else { continue }
                let info = parts[1].trimmingCharacters(in: .whitespaces)
                let split = info.components(separatedBy: ": https://")
                guard split.count == 2 else { continue }
                // Le nom peut contenir des espaces ; seul le dernier segment
                // est la version.
                let words = split[0].components(separatedBy: " ")
                updates.append(ModUpdateInfo(name: words.dropLast().joined(separator: " "),
                                             version: words.last ?? "",
                                             url: "https://" + Self.urlHead(split[1])))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Respiration du format, pas la fin du bloc.
                continue
            } else if !line.contains("ALERT SMAPI") {
                inBlock = false
            }
        }
        return updates
    }

    /// L'URL seule, coupée au premier blanc.
    ///
    /// SMAPI accole la version **installée** derrière l'adresse :
    /// `… /releases (you have 1.6.1-unofficial-2.dphill)`. Prise telle quelle,
    /// la parenthèse faisait partie de l'URL — et `URL(string:)` ne la refuse
    /// pas, il **encode l'espace** : le bouton « Ouvrir la page » menait à un
    /// 404 (`/releases%20(you%20have%201.6.1-unofficial-2.dphill)`) et le lien
    /// cliquable affichait cette bouillie en guise de libellé. Mesuré sur le
    /// journal de l'auteur : **la seule mise à jour annoncée était dans ce
    /// cas**.
    ///
    /// La version entre parenthèses n'est pas reprise : `ModUpdateInfo.version`
    /// est la version **disponible**, ce que l'écran dit explicitement.
    private static func urlHead(_ tail: String) -> String {
        String(tail.prefix { !$0.isWhitespace })
    }
}
