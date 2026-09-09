import Testing
@testable import StarHubTHCore

/// L'écran Réglages a grossi par ajouts successifs : onze sections de premier
/// niveau dans leur ordre d'arrivée. La spec de refonte (§6) demande des « sections unifiées,
/// groupées par nature » — ces tests tiennent la règle, que la vue ne peut pas
/// tenir seule (une vue SwiftUI n'est pas testable dans ce dépôt).
@Suite("Ordre des sections de Réglages")
struct SettingsSectionOrderTests {

    @Test("chaque section appartient à exactement un groupe")
    func everySectionIsPlacedExactlyOnce() {
        let placed = SettingsGroup.allCases.flatMap { SettingsSectionOrder.sections(in: $0) }
        // Le compte ET l'ensemble : le premier attrape un doublon, le second
        // une section oubliée. Un doublon compensé par un oubli passerait le
        // seul test de l'ensemble.
        #expect(placed.count == SettingsSection.allCases.count)
        #expect(Set(placed) == Set(SettingsSection.allCases))
    }

    @Test("aucun groupe n'est vide")
    func noGroupIsEmpty() {
        for group in SettingsGroup.allCases {
            #expect(!SettingsSectionOrder.sections(in: group).isEmpty,
                    "le groupe \(group.rawValue) rendrait un titre sans rien dessous")
        }
    }

    @Test("le dossier du jeu vient avant SMAPI, qui vient avant le lancement")
    func gameGroupReadsInGestureOrder() {
        // On ne peut pas installer SMAPI sans dossier de jeu, ni lancer sans
        // SMAPI : l'ordre de lecture suit l'ordre des gestes, pas l'alphabet.
        let game = SettingsSectionOrder.sections(in: .game)
        guard let folder = game.firstIndex(of: .gameFolder),
              let smapi = game.firstIndex(of: .smapi),
              let launch = game.firstIndex(of: .launch) else {
            Issue.record("les trois sections du parcours d'installation ont quitté le groupe Jeu")
            return
        }
        #expect(folder < smapi)
        #expect(smapi < launch)
    }

    @Test("les groupes sont rendus dans un ordre stable")
    func groupsAreOrdered() {
        #expect(SettingsSectionOrder.groups == [.game, .content, .data, .about])
    }

    @Test("les réglages de développeur ne sont pas dans le premier groupe")
    func developerIsNotUpFront() {
        // Ils étaient au milieu de l'écran, entre la sauvegarde et le
        // comportement des mods ; ce sont les moins utilisés de tous.
        #expect(!SettingsSectionOrder.sections(in: .game).contains(.developer))
        #expect(SettingsSectionOrder.sections(in: .data).contains(.developer))
    }

    @Test("le glossaire et le secours ne sont pas des sections de premier niveau")
    func nestedSectionsAreNotHoisted() {
        // Ils vivent DANS « Traduction assistée » (LocalAISettingsSection) :
        // leur donner un cas ici les ferait rendre deux fois, ou obligerait à
        // éclater cette vue — la refonte de parcours que la spec §9 exclut.
        // Le test ne peut pas nommer un cas absent ; il tient le compte.
        #expect(SettingsSection.allCases.count == 11)
        #expect(SettingsSectionOrder.sections(in: .content) == [.nexus, .translationAI, .modBehavior])
    }

    @Test("l'ordre à l'intérieur d'un groupe est stable d'un appel à l'autre")
    func sectionsAreDeterministic() {
        // Le rendu se fait par ForEach : un ordre qui change entre deux appels
        // ferait sauter les sections à chaque rafraîchissement de la vue.
        for group in SettingsGroup.allCases {
            #expect(SettingsSectionOrder.sections(in: group)
                    == SettingsSectionOrder.sections(in: group))
        }
    }
}
