import Foundation

/// Traduit le schéma d'un content pack avec le `i18n/` du pack lui-même.
///
/// **Pourquoi ce type existe** : les `Name` et `Description` d'un `ConfigSchema`
/// ne sont pas toujours du texte. Content Patcher y accepte le jeton
/// `{{i18n: config.Appearance.Name}}`, qu'il résout à l'exécution contre la
/// table du pack — et que l'éditeur affichait tel quel, donc **moins lisible
/// que la clé brute** qu'il montrait avant. Mesuré sur le parc : **9 des 210
/// packs à schéma** posent des jetons, 285 en tout, tous dans `Name` et
/// `Description` (aucun dans `Section` ni `AllowValues`) ; les 9 ont un
/// `i18n/fr.json`.
///
/// **Ce que la mesure a rapporté en plus** : Content Patcher cherche aussi
/// `config.<clé>.name` **sans qu'aucun jeton ne le demande**, par convention —
/// c'est ainsi qu'un pack traduit son menu de réglages. Sur les 116 packs du
/// parc ayant une table, **1888 des 2061 clés y trouvent un libellé** et 1581
/// une description, là où les `Name` explicites du schéma ne couvrent que 173
/// tokens sur tout le parc. La convention rapporte donc dix fois plus que les
/// jetons.
public enum ContentPackI18n {

    /// Les fichiers de traduction à essayer, dans l'ordre.
    ///
    /// `default.json` est le nom que SMAPI donne à la langue de repli d'un
    /// pack — pas `en.json`, qui existe aussi mais n'est pas garanti.
    public static func localeCandidates(for language: String) -> [String] {
        var candidates = [language, "default", "en"]
        var seen: Set<String> = []
        candidates = candidates.filter { seen.insert($0).inserted }
        return candidates
    }

    /// Les options, libellés et sections résolus.
    ///
    /// Trois sources par champ, dans cet ordre : le texte du schéma s'il est
    /// explicite et sans jeton, le jeton résolu, puis la convention
    /// `config.<clé>.name`. Un jeton qui ne se résout pas ne s'affiche
    /// **jamais** tel quel — le champ retombe à `nil`, et la rangée montre la
    /// clé, qui est au moins lisible.
    public static func localized(_ options: [ConfigSchemaOption],
                                 with table: [String: String]) -> [ConfigSchemaOption] {
        guard !options.isEmpty else { return options }
        var lowered: [String: String] = [:]
        for (key, value) in table where lowered[key.lowercased()] == nil {
            lowered[key.lowercased()] = value
        }

        return options.map { option in
            ConfigSchemaOption(
                token: option.token,
                name: text(option.name, convention: "config.\(option.token).name", in: lowered),
                description: text(option.description,
                                  convention: "config.\(option.token).description", in: lowered),
                section: option.section.flatMap { sectionTitle(of: $0, in: lowered) },
                allowValues: option.allowValues,
                defaultLiteral: option.defaultLiteral,
                allowBlank: option.allowBlank,
                allowMultiple: option.allowMultiple
            )
        }
    }

    /// Le titre d'une section. ⚠️ Ici la **convention passe devant** le texte
    /// du schéma, à l'inverse d'un libellé : `Section` est un identifiant de
    /// regroupement que Content Patcher cherche systématiquement dans la table
    /// (`config.section.<nom>.name`), pas une étiquette déjà rédigée. 264
    /// sections du parc sont traduites de cette façon.
    ///
    /// `nil` quand un jeton reste sans réponse : les options retombent dans le
    /// groupe sans nom, ce qui vaut mieux qu'un titre de section montrant un
    /// jeton. Aucun cas sur le parc — aucune `Section` n'y porte de jeton.
    private static func sectionTitle(of section: String, in table: [String: String]) -> String? {
        if containsToken(section) {
            guard let resolved = resolve(section, in: table) else { return nil }
            return table["config.section.\(resolved).name".lowercased()] ?? resolved
        }
        return table["config.section.\(section).name".lowercased()] ?? section
    }

    private static func text(_ raw: String?, convention: String,
                             in table: [String: String]) -> String? {
        if let raw, !raw.isEmpty {
            if !containsToken(raw) { return raw }
            if let resolved = resolve(raw, in: table) { return resolved }
        }
        return table[convention.lowercased()]
    }

    private static func containsToken(_ text: String) -> Bool {
        text.contains("{{")
    }

    /// Remplace chaque `{{i18n: clé}}` par sa traduction. `nil` dès qu'un
    /// jeton reste — y compris un jeton qui n'est pas une recherche de
    /// traduction : le parc en porte quatre de la forme
    /// `{{config.Autre.name}}`, qui désigne la valeur d'une autre option.
    private static func resolve(_ text: String, in table: [String: String]) -> String? {
        var out = ""
        var rest = Substring(text)

        while let start = rest.range(of: "{{") {
            guard let end = rest.range(of: "}}", range: start.upperBound..<rest.endIndex) else { return nil }
            out += rest[rest.startIndex..<start.lowerBound]

            let body = rest[start.upperBound..<end.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = body.firstIndex(of: ":"),
                  body[body.startIndex..<separator]
                      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "i18n" else { return nil }
            let key = body[body.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let value = table[key] else { return nil }

            out += value
            rest = rest[end.upperBound...]
        }
        return out + rest
    }
}
