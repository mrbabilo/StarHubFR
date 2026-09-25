import Foundation

/// Une section de l'écran Réglages, identifiée indépendamment de son rendu.
///
/// L'écran a grossi par ajouts successifs — onze sections de premier niveau
/// dans leur ordre d'arrivée, où le dossier du jeu suivait la sauvegarde et les
/// réglages de développeur tombaient au milieu. Nommer les sections ici permet de décider
/// de leur place ailleurs que dans l'ordre d'un `VStack`.
public enum SettingsSection: String, CaseIterable, Sendable {
    // Le jeu et son lancement.
    case gameFolder, smapi, launch, coreExtensions
    // D'où vient le contenu, et comment il est traité.
    //
    // `translationAI` est la section « Traduction assistée » entière : le
    // glossaire et le secours en ligne vivent **dedans** (`LocalAISettingsSection`),
    // pas à côté. Les hisser au premier niveau serait éclater une vue — la
    // refonte de parcours que la spec §9 exclut.
    case nexus, translationAI, modBehavior
    // Le dépannage. « Gestion » et « Sauvegarde » (actions ponctuelles, pas
    // des réglages) sont parties sur Entretien et Sauvegardes du jeu le
    // 2026-09-25 ; le groupe « Données & stockage » avec elles.
    case developer
    // L'app elle-même : son affichage (taille du texte, I-T4), puis ses infos.
    case display, appInfo
}

/// Le groupe sous lequel une section se lit. La spec de refonte demande des
/// « sections unifiées, groupées par nature » (§6) : c'est ici que « par
/// nature » est écrit — une fois, et sous test.
public enum SettingsGroup: String, CaseIterable, Sendable {
    case game, content, about
}

public enum SettingsSectionOrder {

    /// L'ordre de lecture des groupes, du plus souvent touché au moins souvent.
    public static let groups: [SettingsGroup] = [.game, .content, .about]

    /// Les sections d'un groupe, dans leur ordre de lecture.
    ///
    /// Le groupe `game` suit **l'ordre des gestes**, pas l'alphabet : on
    /// choisit un dossier de jeu, puis on installe SMAPI dedans, puis on lance,
    /// et les extensions cœur viennent une fois que tout tourne. Quelqu'un qui
    /// découvre l'écran le lit dans cet ordre-là. Les tests tiennent cette
    /// contrainte explicitement.
    /// Le groupe — donc l'onglet — où vit une section : ce qu'un lien vers
    /// une section (Découvrir → clé API Nexus) doit ouvrir avant de défiler.
    public static func group(of section: SettingsSection) -> SettingsGroup {
        groups.first { sections(in: $0).contains(section) } ?? .game
    }

    public static func sections(in group: SettingsGroup) -> [SettingsSection] {
        switch group {
        case .game:    return [.gameFolder, .smapi, .launch, .coreExtensions]
        case .content: return [.nexus, .translationAI, .modBehavior]
        case .about:   return [.display, .developer, .appInfo]
        }
    }
}
