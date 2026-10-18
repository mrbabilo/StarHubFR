import Testing
@testable import StarHubTHCore

/// N-00 (audit UX 2026-10-16) : « Retour » et le ✕ d'une fiche suivent une
/// seule règle. Une fiche ouverte par un saut ramène à la page d'origine ;
/// ouverte depuis la liste, elle se ferme seulement.
struct NavigationHistoryTests {

    private func visited(_ pages: SidebarDestination...) -> NavigationHistory {
        var history = NavigationHistory()
        for page in pages { history.didEnter(page) }
        return history
    }

    @Test func enteringAPageStacksItAndClearsForward() {
        var history = visited(.mods, .updates)
        _ = history.back(from: .none)
        history.didEnter(.mods)          // la page rendue par le retour
        history.didEnter(.profiles)      // une nouvelle page efface l'avant
        #expect(history.backStack == [.home, .mods, .profiles])
        #expect(!history.canGoForward)
    }

    @Test func backFromAPageReturnsThePreviousOneOnce() {
        var history = visited(.mods, .updates)
        #expect(history.back(from: .none) == .init(close: .none, goTo: .mods))
        history.didEnter(.mods)          // pas empilée : vient du retour
        #expect(history.backStack == [.home, .mods])
        #expect(history.forwardStack == [.updates])
    }

    @Test func backAtTheFirstPageGoesNowhere() {
        var history = NavigationHistory()
        #expect(history.back(from: .none) == .init(close: .none, goTo: nil))
        #expect(!history.canGoBack(from: .none))
    }

    /// Le cas de N-00 : Alertes → « Voir le mod » → ✕ ramène aux Alertes.
    @Test func closingAJumpedToDetailReturnsToItsOrigin() {
        var history = visited(.systemAlerts, .mods)
        history.detailOpenedByJump = true
        #expect(history.back(from: .modDetail) == .init(close: .modDetail, goTo: .systemAlerts))
        #expect(!history.detailOpenedByJump)
    }

    @Test func closingADetailOpenedFromTheListStaysOnTheList() {
        var history = visited(.mods)
        #expect(history.back(from: .modDetail) == .init(close: .modDetail, goTo: nil))
    }

    /// L'éditeur de config posé sur une fiche se ferme sur la fiche, jamais
    /// sur la page d'origine : le saut reste en attente pour la fiche.
    @Test func aConfigEditorOverADetailClosesOntoTheDetail() {
        var history = visited(.systemAlerts, .mods)
        history.detailOpenedByJump = true
        #expect(history.back(from: .modConfig(detailUnderneath: true))
                == .init(close: .modConfig(detailUnderneath: true), goTo: nil))
        #expect(history.detailOpenedByJump)
        #expect(history.back(from: .modConfig(detailUnderneath: false))
                == .init(close: .modConfig(detailUnderneath: false), goTo: .systemAlerts))
    }

    @Test func saveDetailsCloseWithoutChangingPage() {
        var history = visited(.mods, .saves)
        history.detailOpenedByJump = true
        #expect(history.back(from: .saveEditor) == .init(close: .saveEditor, goTo: nil))
    }

    @Test func forwardReturnsThePageLeftByBack() {
        var history = visited(.mods, .updates)
        _ = history.back(from: .none)
        history.didEnter(.mods)
        #expect(history.forward() == .updates)
        history.didEnter(.updates)       // pas empilée deux fois
        #expect(history.backStack == [.home, .mods, .updates])
        #expect(history.forward() == nil)
    }
}
