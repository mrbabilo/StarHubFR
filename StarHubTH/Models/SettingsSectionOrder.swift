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
    // Ce que l'app garde sur le disque.
    case management, backup, developer
    // L'app elle-même.
    case appInfo
}

/// Le groupe sous lequel une section se lit. La spec de refonte demande des
/// « sections unifiées, groupées par nature » (§6) : c'est ici que « par
/// nature » est écrit — une fois, et sous test.
public enum SettingsGroup: String, CaseIterable, Sendable {
    case game, content, data, about
}

public enum SettingsSectionOrder {

    /// L'ordre de lecture des groupes, du plus souvent touché au moins souvent.
    public static let groups: [SettingsGroup] = [.game, .content, .data, .about]

    /// Les sections d'un groupe, dans leur ordre de lecture.
    ///
    /// Le groupe `game` suit **l'ordre des gestes**, pas l'alphabet : on
    /// choisit un dossier de jeu, puis on installe SMAPI dedans, puis on lance,
    /// et les extensions cœur viennent une fois que tout tourne. Quelqu'un qui
    /// découvre l'écran le lit dans cet ordre-là. Les tests tiennent cette
    /// contrainte explicitement.
    public static func sections(in group: SettingsGroup) -> [SettingsSection] {
        switch group {
        case .game:    return [.gameFolder, .smapi, .launch, .coreExtensions]
        case .content: return [.nexus, .translationAI, .modBehavior]
        case .data:    return [.management, .backup, .developer]
        case .about:   return [.appInfo]
        }
    }
}
