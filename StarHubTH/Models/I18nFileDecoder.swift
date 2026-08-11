import Foundation

/// Décode un fichier i18n **comme SMAPI le décode**.
///
/// SMAPI lit ces fichiers avec `File.ReadAllText`, qui honore la marque d'ordre
/// des octets puis se rabat sur UTF-8 **en remplaçant** les octets invalides —
/// sans jamais échouer. Vérifié en exécutant ce chemin avec la
/// `Newtonsoft.Json.dll` du jeu.
///
/// Notre lecture s'arrêtait à `String(data:encoding:.utf8)`, qui rend `nil` au
/// premier octet fautif. Quatre fichiers du parc en faisaient les frais :
///
/// - `DestroyableBushes/i18n/ru.json` est en **UTF-16 LE avec marque** — le jeu
///   le lit sans perdre un caractère, nous le refusions entièrement ;
/// - trois `es.json` sont dans un **jeu 8 bits hérité** — le jeu les charge avec
///   les accents remplacés, ce qui est une anomalie du mod, pas un échec de
///   lecture, et mérite d'être distingué de l'un comme de l'autre.
public enum I18nFileDecoder {
    public struct Decoded: Equatable, Sendable {
        public let text: String
        /// Vrai quand des octets ont dû être remplacés : le fichier se charge,
        /// mais son texte est abîmé. C'est ce qu'il faut dire à l'utilisateur —
        /// ni « illisible », ni « parfait ».
        public let hasReplacedBytes: Bool

        public init(text: String, hasReplacedBytes: Bool) {
            self.text = text
            self.hasReplacedBytes = hasReplacedBytes
        }
    }

    /// Le contenu texte d'un fichier i18n. Ne rend `nil` que si les octets ne
    /// forment rien d'exploitable, ce qui n'arrive pas en pratique — la
    /// substitution garantit un résultat.
    public static func decode(_ data: Data) -> Decoded? {
        if let marked = decodeWithByteOrderMark(data) {
            return Decoded(text: marked, hasReplacedBytes: false)
        }

        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data

        // Le décodage strict dit s'il y a eu substitution : il rend `nil` au
        // premier octet fautif. `String(decoding:as:)` ne rend jamais `nil` —
        // il substitue, exactement comme `File.ReadAllText`. Comparer les deux
        // est plus sûr que de chercher un U+FFFD dans le résultat, qu'un fichier
        // pourrait légitimement contenir.
        if let strict = String(data: Data(body), encoding: .utf8) {
            return Decoded(text: strict, hasReplacedBytes: false)
        }
        return Decoded(text: String(decoding: body, as: UTF8.self), hasReplacedBytes: true)
    }

    /// UTF-16 ou UTF-32 annoncé par une marque d'ordre des octets.
    ///
    /// L'ordre des tests reproduit celui de `StreamReader.DetectEncoding` côté
    /// .NET, mesuré avec `File.ReadAllText` sous mono : la marque UTF-32 LE
    /// **commence** par celle de l'UTF-16 LE (`FF FE`), et seuls les deux octets
    /// suivants les séparent. Les prendre pour de l'UTF-16 intercalait un
    /// caractère nul entre chaque lettre ; la marque UTF-32 BE, elle, n'était
    /// pas reconnue du tout et le fichier partait en UTF-8 avec substitution.
    private static func decodeWithByteOrderMark(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count >= 2 else { return nil }

        if bytes.count >= 4 {
            if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
                return String(data: data.dropFirst(4), encoding: .utf32BigEndian)
            }
            if bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00 {
                return String(data: data.dropFirst(4), encoding: .utf32LittleEndian)
            }
        }

        switch (bytes[0], bytes[1]) {
        case (0xFF, 0xFE):
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        case (0xFE, 0xFF):
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        default:
            return nil
        }
    }
}
