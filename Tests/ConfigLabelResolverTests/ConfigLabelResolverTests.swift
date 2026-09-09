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

    @Test func unknownSuffixesAreIgnored() {
        let index = ConfigLabelResolver.index(
            defaultFile: ["config.fastWarp.flavor": "nope"],
            localizedFile: [:])
        #expect(ConfigLabelResolver.labels(for: "fastWarp", in: index) == nil)
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
}
