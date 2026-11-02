import Foundation

/// Un réglage de `config.json` qui porte un secret : clé d'API, jeton
/// d'accès, mot de passe. Keybind Sheet (décompilé le 2026-11-02) garde ses
/// clés DeepL, Google, OpenAI et DeepSeek en clair dans son `config.json` ;
/// l'éditeur de config les affichait telles quelles.
///
/// Des formes précises, pas des mots seuls : sur les 637 `config.json` du
/// parc, « secret » et « token » ne désignent que des lieux et des objets du
/// jeu (`EnableSeaCaveSecrets`, `StarToken`). Un segment du chemin suffit :
/// `TranslationApiKeys.DeepL` est un secret par son parent.
public enum ConfigSecretField {
    static let markers = ["apikey", "apitoken", "accesstoken", "authtoken", "bearertoken",
                          "password", "passwd", "clientsecret", "apisecret", "privatekey"]

    public static func isSecret(_ keyPath: [String]) -> Bool {
        keyPath.contains { segment in
            let folded = segment.lowercased().filter { $0.isLetter || $0.isNumber }
            return markers.contains { folded.contains($0) }
        }
    }
}
