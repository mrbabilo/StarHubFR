import Testing
import Foundation
@testable import StarHubTHCore

/// C4-T1 — le rapprochement tige i18n ↔ clé de configuration. Chaque règle
/// vient d'une mesure sur le parc (2026-08-28) confirmée par décompilation
/// (2026-09-04) : insensible à la casse, suffixes bornés, français gagnant
/// champ par champ, repli assumé sur la clé brute quand rien ne retombe.
struct ConfigLabelResolverTests {

    // MARK: - Construction de l'index

    @Test func extractsStemAndSuffixes() {
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "config.fastWarp.name": "Fast warp",
                "config.fastWarp.description": "Warp faster.",
            ],
            localizedFile: [:])
        let labels = ConfigLabelResolver.labels(for: "fastWarp", in: index)
        #expect(labels?.text == "Fast warp")
        #expect(labels?.detail == "Warp faster.")
    }

    @Test func matchingIsCaseInsensitiveBothWays() {
        let index = ConfigLabelResolver.index(
            defaultFile: ["CONFIG.EnableFastWarp.NAME": "Fast warp"],
            localizedFile: [:])
        // UltraSmooth écrit camelCase dans l'i18n, le config.json porte du
        // PascalCase : la tige retombe quand même.
        #expect(ConfigLabelResolver.labels(for: "EnableFastWarp", in: index)?.text == "Fast warp")
        #expect(ConfigLabelResolver.labels(for: "enablefastwarp", in: index)?.text == "Fast warp")
    }

    @Test func nestedStemsCutAtTheLastDot() {
        let index = ConfigLabelResolver.index(
            defaultFile: ["config.heal.amount.name": "Heal amount"],
            localizedFile: [:])
        // La tige d'une clé à trois maillons est tout ce qui reste — le
        // rapprochement se fait sur la clé de config `heal.amount`.
        #expect(ConfigLabelResolver.labels(for: "heal.amount", in: index)?.text == "Heal amount")
        #expect(ConfigLabelResolver.labels(for: "amount", in: index) == nil)
    }

    @Test func keysOutsideTheConfigPrefixAreIgnored() {
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "movie.fastWarp.name": "Not a config label",
                "fastWarp.name": "Neither",
            ],
            localizedFile: [:])
        #expect(ConfigLabelResolver.labels(for: "fastWarp", in: index) == nil)
    }

    @Test func bareConfigKeysWithoutSuffixAreIgnored() {
        let index = ConfigLabelResolver.index(
            defaultFile: ["config.fastWarp": "not a label"],
            localizedFile: [:])
        #expect(ConfigLabelResolver.labels(for: "fastWarp", in: index) == nil)
    }

    @Test func unknownSuffixesOnlyFeedValueLabels() {
        let index = ConfigLabelResolver.index(
            defaultFile: ["config.fastWarp.flavor": "nope"],
            localizedFile: [:])
        // C4-T14 — gardé comme libellé de valeur candidat, jamais comme
        // libellé ni aide du champ.
        let labels = ConfigLabelResolver.labels(for: "fastWarp", in: index)
        #expect(labels?.text == "")
        #expect(labels?.detail == nil)
        #expect(labels?.values == ["flavor": "nope"])
    }

    @Test func theValuesFormIsAlwaysAValueLabel() {
        // `config.<clé>.values.<valeur>` (Content Patcher, repris par les mods
        // Pathoschild) : même une valeur nommée `Name` n'y est pas le libellé
        // du champ.
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "config.theme.values.Joja": "Joja",
                "config.theme.values.Name": "By name",
            ],
            localizedFile: [:])
        let labels = ConfigLabelResolver.labels(for: "Theme", in: index)
        #expect(labels?.text == "")
        #expect(labels?.values == ["joja": "Joja", "name": "By name"])
        #expect(ConfigLabelResolver.labels(for: "theme.values", in: index) == nil)
    }

    @Test func frenchOverridesValueByValue() {
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "config.style.scale2x": "Scale2x (crisp)",
                "config.style.soft4x": "Soft4x (smooth)",
            ],
            localizedFile: ["config.style.scale2x": "Scale2x (net)"])
        let values = ConfigLabelResolver.labels(for: "style", in: index)?.values
        #expect(values == ["scale2x": "Scale2x (net)", "soft4x": "Soft4x (smooth)"])
    }

    // MARK: - Suffixes

    @Test func labelFallsThroughNameThenLabelThenTitle() {
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "config.a.title": "Title text",
                "config.a.label": "Label text",
                "config.a.name": "Name text",
            ],
            localizedFile: [:])
        // `name` gagne : c'est la convention dominante des menus de config.
        #expect(ConfigLabelResolver.labels(for: "a", in: index)?.text == "Name text")
    }

    @Test func detailAcceptsDescriptionTooltipAndDesc() {
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "config.a.description": "Long",
                "config.b.tooltip": "Tooltip",
                "config.c.desc": "Short",
            ],
            localizedFile: [:])
        #expect(ConfigLabelResolver.labels(for: "a", in: index)?.detail == "Long")
        #expect(ConfigLabelResolver.labels(for: "b", in: index)?.detail == "Tooltip")
        #expect(ConfigLabelResolver.labels(for: "c", in: index)?.detail == "Short")
    }

    // MARK: - Français

    @Test func frenchOverridesFieldByField() {
        let index = ConfigLabelResolver.index(
            defaultFile: [
                "config.warp.name": "Fast warp",
                "config.warp.description": "Warp faster.",
            ],
            localizedFile: ["config.warp.name": "Téléportation rapide"])
        let labels = ConfigLabelResolver.labels(for: "warp", in: index)
        // Le label traduit n'entraîne pas sa description : la description
        // anglaise reste meilleure qu'un vide.
        #expect(labels?.text == "Téléportation rapide")
        #expect(labels?.detail == "Warp faster.")
    }

    // MARK: - Orphelines et replis

    @Test func orphanDescriptionKeepsTheRawKeyAsLabel() throws {
        let index = ConfigLabelResolver.index(
            defaultFile: ["config.lone.tooltip": "What this does"],
            localizedFile: [:])
        let labels = try #require(ConfigLabelResolver.labels(for: "lone", in: index))
        // La description orpheline aide quand même — sous la clé brute.
        #expect(labels.text.isEmpty)
        #expect(labels.detail == "What this does")
    }

    @Test func unknownConfigKeyResolvesToNothing() {
        let index = ConfigLabelResolver.index(
            defaultFile: ["config.other.name": "Other"],
            localizedFile: [:])
        // Le repli sur la clé brute est la règle : SLO choisit librement et
        // ne retombe pas — personne ne promet 100 %.
        #expect(ConfigLabelResolver.labels(for: "EnableFastWarpTransitions", in: index) == nil)
    }

    // MARK: - Intégration : les rangées de l'éditeur

    @Test func editorRowsPreferSchemaThenI18nThenRawKey() throws {
        guard let tree = ConfigJSONTree.parse("""
        {
          "EnableFastWarp": true,
          "OrphanKey": "text",
          "SchemaNamed": 3
        }
        """) else { Issue.record("arbre non parsé"); return }
        let labels = ConfigLabelResolver.index(
            defaultFile: [
                "config.EnableFastWarp.name": "Fast warp",
                "config.OrphanKey.tooltip": "What this does",
            ],
            localizedFile: [:])
        let schema = [
            ConfigSchemaOption(token: "SchemaNamed", name: "Named by schema",
                               description: nil, section: nil, allowValues: [],
                               defaultLiteral: nil, allowBlank: nil, allowMultiple: nil),
        ]
        let rows = ConfigEditorModel.groups(of: tree, describedBy: schema,
                                            labeledBy: labels).flatMap(\.rows)

        let fastWarp = try #require(rows.first { $0.keyPath == ["EnableFastWarp"] })
        #expect(fastWarp.label == "Fast warp")

        let orphan = try #require(rows.first { $0.keyPath == ["OrphanKey"] })
        // Clé brute en libellé, mais l'aide du mod est là.
        #expect(orphan.label == "OrphanKey")
        #expect(orphan.description == "What this does")

        // Le schéma gagne : son `Name` est un identifiant de token, pas un
        // libellé de repli.
        let schemaNamed = try #require(rows.first { $0.keyPath == ["SchemaNamed"] })
        #expect(schemaNamed.label == "Named by schema")
    }

    @Test func menuEntriesTakeTheLabelsOfAllowedValuesOnly() throws {
        guard let tree = ConfigJSONTree.parse("""
        { "Placement": "Loose", "SkipTo": "Title" }
        """) else { Issue.record("arbre non parsé"); return }
        let labels = ConfigLabelResolver.index(
            defaultFile: [
                "config.placement.name": "Placement rule",
                "config.placement.strict": "Strict (vanilla)",
                "config.placement.loose": "Loose",
                "config.placement.flavor": "Not a choice",
                // Une valeur homonyme d'un suffixe connu : `title` est le
                // libellé du champ, jamais celui de l'entrée `Title`.
                "config.skipTo.title": "Skip to",
            ],
            localizedFile: ["config.placement.loose": "Souple"])
        let rows = ConfigEditorModel.groups(
            of: tree, describedBy: [], labeledBy: labels,
            gmcmChoices: ["Placement": ["Strict", "Loose", "Anarchy"],
                          "SkipTo": ["Title", "Load"]]).flatMap(\.rows)

        let placement = try #require(rows.first { $0.keyPath == ["Placement"] })
        #expect(placement.label == "Placement rule")
        #expect(placement.choiceLabels == ["strict": "Strict (vanilla)", "loose": "Souple"])
        #expect(placement.choiceLabel(for: "Anarchy") == nil)

        let skipTo = try #require(rows.first { $0.keyPath == ["SkipTo"] })
        #expect(skipTo.choiceLabel(for: "Title") == nil)
    }

    @Test func aSchemaMenuTakesThePackLabelsNotTheI18nIndex() throws {
        guard let tree = ConfigJSONTree.parse("""
        { "Shirt": "Warm", "Free": "Warm" }
        """) else { Issue.record("arbre non parsé"); return }
        var shirt = ConfigSchemaOption(token: "Shirt", name: nil, description: nil, section: nil,
                                       allowValues: ["Warm", "Cold"], defaultLiteral: nil,
                                       allowBlank: nil, allowMultiple: nil)
        shirt.valueLabels = ["warm": "Chaud"]
        let labels = ConfigLabelResolver.index(
            defaultFile: ["config.shirt.cold": "From i18n", "config.free.warm": "Unused"],
            localizedFile: [:])
        let rows = ConfigEditorModel.groups(of: tree, describedBy: [shirt],
                                            labeledBy: labels).flatMap(\.rows)

        let row = try #require(rows.first { $0.keyPath == ["Shirt"] })
        #expect(row.choiceLabels == ["warm": "Chaud"])
        // Pas de menu, pas de libellé d'entrée : un champ texte reste brut.
        let free = try #require(rows.first { $0.keyPath == ["Free"] })
        #expect(free.choiceLabels.isEmpty)
    }
}
