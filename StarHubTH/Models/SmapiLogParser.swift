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
