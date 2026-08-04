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
        if let markedUTF16 = decodeUTF16WithMark(data) {
            return Decoded(text: markedUTF16, hasReplacedBytes: false)
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

    /// UTF-16 avec marque d'ordre des octets, dans les deux boutismes.
    private static func decodeUTF16WithMark(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let first = data[data.startIndex]
        let second = data[data.index(after: data.startIndex)]
        switch (first, second) {
        case (0xFF, 0xFE):
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        case (0xFE, 0xFF):
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        default:
            return nil
        }
    }
}
