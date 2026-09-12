import Foundation

/// Ce qu'un changement d'onglet décide des vues de détail (P8, la reprise des
/// vues).
///
/// **Pourquoi une règle et non cinq affectations.** Changer d'onglet remet à
/// `nil` les cinq états de détail — poser l'un d'eux *puis* changer
/// `currentTab` ne marche donc jamais. Trois fonctionnalités s'y sont cassé
/// les dents (B3-T4 la traduction, T8 l'éditeur de config, H-T6b la fiche
/// depuis les alertes système), et chacune a été rattrapée par une intention
/// « en attente » reconsommée **dans** le changement d'onglet lui-même. Le
/// tout vivait en quarante lignes dans `MainView.handleTabChange`, hors de
/// portée d'un test.
///
/// **Les trois intentions ne se comportent pas pareil**, et c'est
/// délibéré — les confondre rejouerait l'un des trois bugs :
///
/// - `translationFocus` ouvre la fiche et **survit** : c'est la vue qui la
///   consomme plus tard, pour présélectionner l'onglet Traduction. L'effacer
///   ici rouvrirait la fiche sur « État ».
/// - `configFocus` ouvre l'éditeur et est **effacée aussitôt** : rien ne la
///   consomme plus tard, et la garder ferait rejouer l'ouverture à chaque
///   retour sur l'onglet.
/// - `modDetailFocus` ouvre la fiche et est **effacée aussitôt** ; en plus,
///   si la résolution ne trouve rien, l'onglet demandé part avec elle —
///   sinon la prochaine fiche ouverte à la main s'ouvrirait sur « État » sans
///   raison.
public enum TabChangePlan {

    /// Les intentions posées avant le changement d'onglet.
    public struct Pending: Equatable, Sendable {
        public let translationFocus: String?
        public let configFocus: String?
        public let modDetailFocus: String?

        public init(translationFocus: String? = nil,
                    configFocus: String? = nil,
                    modDetailFocus: String? = nil) {
            self.translationFocus = translationFocus
            self.configFocus = configFocus
            self.modDetailFocus = modDetailFocus
        }
    }

    /// Ce qu'il faut faire. Les cinq états de détail sont effacés dans tous
    /// les cas — ce n'est pas dans le plan parce que ce n'est pas une
    /// décision : c'est l'invariant du changement d'onglet.
    public struct Plan: Equatable, Sendable {
        /// La fiche à ouvrir, déjà résolue.
        public let openModDetail: ModItem?
        /// L'éditeur de configuration à ouvrir, déjà résolu.
        public let openModConfig: ModItem?
        public let clearsConfigFocus: Bool
        public let clearsModDetailFocus: Bool
        /// L'onglet de fiche demandé n'a plus de fiche à ouvrir : il doit
        /// partir, sinon il s'appliquerait à la prochaine ouverture manuelle.
        public let clearsPendingDetailTab: Bool

        public static let nothing = Plan(openModDetail: nil, openModConfig: nil,
                                         clearsConfigFocus: false,
                                         clearsModDetailFocus: false,
                                         clearsPendingDetailTab: false)
    }

    /// Décide, pour l'onglet où l'on arrive.
    ///
    /// Hors de l'onglet des mods, rien n'est reconsommé : les intentions
    /// attendent. Elles visent toutes une vue de cet onglet-là.
    ///
    /// - Parameter mods: les mods de **premier niveau**. Les deux intentions
    ///   qui désignent un dossier cherchent dans le parc **déplié** — un
    ///   composant de pack se traduit et se configure comme un mod — tandis
    ///   que `ModFocusResolver` veut la liste de premier niveau et déplie
    ///   lui-même. Cette asymétrie est celle du code d'origine ; l'aplatir
    ///   ferait chercher un pack parmi ses enfants, où il n'existe pas.
    public static func decide(entering tab: SidebarDestination,
                              pending: Pending,
                              mods: [ModItem]) -> Plan {
        guard tab == .mods else { return .nothing }
        let flattened = mods.flattenedMods

        // La traduction d'abord : elle ne s'efface pas, et une demande de
        // fiche explicite (`modDetailFocus`) doit pouvoir la remplacer.
        var detail = pending.translationFocus.flatMap { folderName in
            flattened.first { $0.folderName == folderName }
        }

        let config = pending.configFocus.flatMap { folderName in
            flattened.first { $0.folderName == folderName }
        }

        var clearsDetailTab = false
        if let query = pending.modDetailFocus {
            // `ModFocusResolver` accepte le nom affiché **et** le nom de
            // dossier : une ligne SMAPI porte l'un, une ligne de conflit
            // l'autre.
            detail = ModFocusResolver.resolve(query, in: mods)
            clearsDetailTab = detail == nil
        }

        return Plan(openModDetail: detail,
                    openModConfig: config,
                    clearsConfigFocus: pending.configFocus != nil,
                    clearsModDetailFocus: pending.modDetailFocus != nil,
                    clearsPendingDetailTab: clearsDetailTab)
    }
}
