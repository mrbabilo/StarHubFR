import Testing
import Foundation
@testable import StarHubTHCore

/// Ce qu'un changement d'onglet décide des vues de détail.
///
/// La règle vivait en quarante lignes dans `MainView.handleTabChange`, hors
/// de portée d'un test — alors que trois fonctionnalités s'y étaient déjà
/// cassé les dents et que chacune y a laissé une correction que rien ne
/// tenait. Les trois intentions **ne se comportent pas pareil** : les
/// confondre rejouerait l'un des trois bugs.
@Suite struct TabChangePlanTests {

    private func mod(_ folder: String, name: String? = nil,
                     children: [ModItem]? = nil) -> ModItem {
        ModItem(uniqueId: "id.\(folder)", name: name ?? folder, folderName: folder,
                version: "1.0", author: "", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: true, dependencies: [],
                children: children, isGroup: children != nil)
    }

    /// Un pack et un mod simple : le composant n'existe que dans le parc
    /// **déplié**, l'en-tête que dans celui de premier niveau.
    private var parc: [ModItem] {
        [mod("Pack", children: [mod("Composant")]), mod("Simple")]
    }

    // MARK: - Hors de l'onglet des mods, les intentions attendent

    /// Elles visent toutes une vue de l'onglet des mods : les reconsommer
    /// ailleurs les gaspillerait sans rien ouvrir.
    @Test func nothingIsConsumedOutsideTheModsTab() {
        let plan = TabChangePlan.decide(
            entering: .saves,
            pending: .init(translationFocus: "Simple", configFocus: "Simple",
                           modDetailFocus: "Simple"),
            mods: parc)
        #expect(plan == .nothing)
    }

    // MARK: - Les trois intentions, chacune son sort

    /// La traduction **survit** : c'est la vue qui la consomme plus tard,
    /// pour présélectionner l'onglet Traduction. L'effacer ici rouvrirait la
    /// fiche sur « État ».
    @Test func theTranslationIntentionOpensTheSheetAndSurvives() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(translationFocus: "Simple"), mods: parc)
        #expect(plan.openModDetail?.folderName == "Simple")
        #expect(plan.clearsModDetailFocus == false)
        #expect(plan.clearsConfigFocus == false)
    }

    /// La configuration est **effacée aussitôt** : rien ne la consomme plus
    /// tard, et la garder ferait rejouer l'ouverture à chaque retour sur
    /// l'onglet.
    @Test func theConfigIntentionOpensTheEditorAndIsCleared() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(configFocus: "Simple"), mods: parc)
        #expect(plan.openModConfig?.folderName == "Simple")
        #expect(plan.clearsConfigFocus)
    }

    @Test func theModDetailIntentionOpensTheSheetAndIsCleared() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(modDetailFocus: "Simple"), mods: parc)
        #expect(plan.openModDetail?.folderName == "Simple")
        #expect(plan.clearsModDetailFocus)
        #expect(plan.clearsPendingDetailTab == false)
    }

    /// Le cas qui porte : une demande introuvable n'ouvrira aucune fiche,
    /// donc personne ne consommera l'onglet demandé — il doit partir, sinon
    /// la prochaine fiche ouverte **à la main** s'ouvrirait sur « État » sans
    /// raison.
    @Test func anUnresolvableDetailRequestAlsoDropsTheRequestedTab() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(modDetailFocus: "JamaisInstalle"),
            mods: parc)
        #expect(plan.openModDetail == nil)
        #expect(plan.clearsModDetailFocus)
        #expect(plan.clearsPendingDetailTab)
    }

    /// Et l'inverse : une demande qui aboutit **garde** l'onglet, c'est tout
    /// son intérêt. Le cas voisin qui ne doit pas changer.
    @Test func aResolvedDetailRequestKeepsTheRequestedTab() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(modDetailFocus: "Pack"), mods: parc)
        #expect(plan.openModDetail?.folderName == "Pack")
        #expect(plan.clearsPendingDetailTab == false)
    }

    // MARK: - Les deux parcs, asymétrie préservée

    /// Traduction et configuration cherchent dans le parc **déplié** : un
    /// composant de pack se traduit et se configure comme un mod.
    @Test func aPackComponentIsReachableByTranslationAndConfig() {
        let byTranslation = TabChangePlan.decide(
            entering: .mods, pending: .init(translationFocus: "Composant"), mods: parc)
        #expect(byTranslation.openModDetail?.folderName == "Composant")

        let byConfig = TabChangePlan.decide(
            entering: .mods, pending: .init(configFocus: "Composant"), mods: parc)
        #expect(byConfig.openModConfig?.folderName == "Composant")
    }

    /// `ModFocusResolver` reçoit la liste de **premier niveau** et déplie
    /// lui-même : l'en-tête du pack doit rester atteignable — c'est lui
    /// qu'on met en pause, et il n'existe pas parmi ses enfants.
    @Test func thePackHeaderStaysReachableByTheResolver() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(modDetailFocus: "Pack"), mods: parc)
        #expect(plan.openModDetail?.folderName == "Pack")
        #expect(plan.openModDetail?.isGroup == true)
    }

    // MARK: - Quand deux intentions cohabitent

    /// Une demande de fiche explicite **remplace** celle de la traduction :
    /// c'est l'ordre du code d'origine, et la dernière posée est la plus
    /// récente intention de l'utilisateur.
    @Test func anExplicitDetailRequestOverridesTheTranslationOne() {
        let plan = TabChangePlan.decide(
            entering: .mods,
            pending: .init(translationFocus: "Composant", modDetailFocus: "Simple"),
            mods: parc)
        #expect(plan.openModDetail?.folderName == "Simple")
    }

    /// Et si elle est introuvable, elle remplace quand même — par `nil`. Le
    /// comportement du code d'origine, préservé : la fiche de traduction ne
    /// s'ouvre pas derrière le dos d'une demande plus récente.
    @Test func anUnresolvableDetailRequestStillOverridesTheTranslationOne() {
        let plan = TabChangePlan.decide(
            entering: .mods,
            pending: .init(translationFocus: "Composant", modDetailFocus: "JamaisInstalle"),
            mods: parc)
        #expect(plan.openModDetail == nil)
        #expect(plan.clearsPendingDetailTab)
    }

    /// Une demande vide n'ouvre rien : `contains("")` est vrai partout, et la
    /// garde vit dans `ModFocusResolver`.
    @Test func anEmptyDetailRequestOpensNothing() {
        let plan = TabChangePlan.decide(
            entering: .mods, pending: .init(modDetailFocus: "   "), mods: parc)
        #expect(plan.openModDetail == nil)
        #expect(plan.clearsPendingDetailTab)
    }
}
