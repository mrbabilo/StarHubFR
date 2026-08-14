import Foundation

/// Lit le champ `Version` d'un manifest de mod, sous ses deux formes.
///
/// SMAPI accepte une chaîne (`"1.2.3"`) **ou** un objet
/// (`{"MajorVersion": 1, "MinorVersion": 2, "PatchVersion": 3}`). Le scan de
/// la bibliothèque gérait les deux ; la pose d'ancre à l'installation, non —
/// elle faisait `as? String` et abandonnait en silence sur la forme objet,
/// c'est-à-dire précisément là où l'app sait avec certitude ce qu'elle vient
/// d'écrire sur le disque.
///
/// Deux lectures divergentes du même champ, à quinze cents lignes d'écart :
/// ce module existe pour qu'il n'y en ait plus qu'une.
public enum ManifestVersionReader {

    /// - Parameter manifest: le manifest décodé.
    /// - Returns: la version sous forme de chaîne, ou `nil` si le champ est
    ///   absent ou d'un type qu'on ne sait pas lire.
    public static func version(from manifest: [String: Any]) -> String? {
        version(fromField: manifest.caseInsensitiveValue(forKey: "Version"))
    }

    /// Variante prenant le champ déjà extrait, pour les appelants qui l'ont
    /// sous la main.
    public static func version(fromField field: Any?) -> String? {
        if let text = field as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let parts = field as? [String: Any] else { return nil }
        // Les valeurs par défaut sont celles du scan de la bibliothèque —
        // majeure à 1, mineure et correctif à 0 — pour que les deux lectures
        // rendent la même chaîne sur le même manifest.
        let major = intValue(parts.caseInsensitiveValue(forKey: "MajorVersion")) ?? 1
        let minor = intValue(parts.caseInsensitiveValue(forKey: "MinorVersion")) ?? 0
        let patch = intValue(parts.caseInsensitiveValue(forKey: "PatchVersion")) ?? 0
        return "\(major).\(minor).\(patch)"
    }

    /// `JSONSerialization` rend des `NSNumber` ; un manifest écrit à la main
    /// peut aussi porter `"1"` en chaîne. Les deux valent un entier ici.
    private static func intValue(_ raw: Any?) -> Int? {
        if let n = raw as? Int { return n }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
