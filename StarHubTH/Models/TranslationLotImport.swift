import Foundation

/// La relecture d'un lot revenu d'un modèle de chat.
///
/// Deux niveaux de refus, et la distinction est ce qui rend l'import
/// utilisable : ce qui met en cause le **fichier** (mauvais mod, mauvaise
/// langue, empreinte périmée, illisible) le fait rejeter en bloc **avant toute
/// écriture** ; ce qui met en cause **une entrée** (marque dure perdue, clé
/// inventée) écarte cette entrée-là et laisse passer le reste.
public enum TranslationLotImport {

    public struct Accepted: Equatable, Sendable {
        public let component: String?
        public let key: String
        public let source: String
        public let target: String
    }

    public struct Rejection: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            case missingHardMarkers([String])
            case unknownKey
            case sourceAltered
        }
        public let component: String?
        public let key: String
        public let reason: Reason
    }

    public struct Report: Equatable, Sendable {
        public let accepted: [Accepted]
        public let rejected: [Rejection]
    }

    public enum FileRefusal: Error, Equatable, Sendable {
        case unreadable
        case wrongMod
        case wrongLanguage
        case staleDigest
        case unsupportedFormat(Int)
    }

    public static func read(_ data: Data, expecting sent: TranslationLot) throws -> Report {
        guard let lot = decode(data) else { throw FileRefusal.unreadable }
        guard lot.formatVersion == TranslationLot.currentFormatVersion else {
            throw FileRefusal.unsupportedFormat(lot.formatVersion)
        }
        guard lot.mod == sent.mod else { throw FileRefusal.wrongMod }
        guard lot.language == sent.language else { throw FileRefusal.wrongLanguage }
        guard lot.digest == sent.digest else { throw FileRefusal.staleDigest }

        // Les sources envoyées, par identité : c'est elles qui font foi, pas
        // celles que le fichier prétend porter.
        var expected: [String: TranslationLot.Entry] = [:]
        for entry in sent.entries {
            expected[identity(entry.component, entry.key)] = entry
        }

        var accepted: [Accepted] = []
        var rejected: [Rejection] = []
        for entry in lot.entries {
            let target = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { continue }   // travail non fait, pas une erreur
            guard let origin = expected[identity(entry.component, entry.key)] else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .unknownKey))
                continue
            }
            guard origin.source == entry.source else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .sourceAltered))
                continue
            }
            let missing = TranslationTokenCheck
                .mismatches(source: origin.source, target: entry.target)
                .filter { $0.isHard && $0.found < $0.expected }
                .map(\.token)
            guard missing.isEmpty else {
                rejected.append(Rejection(component: entry.component, key: entry.key,
                                          reason: .missingHardMarkers(missing)))
                continue
            }
            accepted.append(Accepted(component: entry.component, key: entry.key,
                                     source: origin.source, target: entry.target))
        }
        return Report(accepted: accepted, rejected: rejected)
    }

    private static func identity(_ component: String?, _ key: String) -> String {
        "\(component ?? "")\u{1F}\(key)"
    }

    /// Un chat rend volontiers son JSON dans une clôture Markdown, précédé
    /// d'une phrase. On garde ce qui va de la première accolade à la dernière.
    private static func decode(_ data: Data) -> TranslationLot? {
        if let lot = try? JSONDecoder().decode(TranslationLot.self, from: data) { return lot }
        guard let text = String(data: data, encoding: .utf8),
              let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}"), first < last else { return nil }
        let carved = String(text[first...last])
        return try? JSONDecoder().decode(TranslationLot.self, from: Data(carved.utf8))
    }
}
