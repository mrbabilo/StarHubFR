import Testing
@testable import StarHubTHCore

/// Épingle le contrat de pagination de `ModListFilters` : tout critère qui
/// change le **nombre** de résultats ramène à la page 1, celui qui ne le
/// change pas (le tri) ne y touche pas. Ce contrat vivait sous forme de cinq
/// `.onChange` séparés dans la vue avant d'être porté par le type — chaque
/// test ci-dessous est une régression qu'un sixième filtre sans sa garde
/// réintroduirait.
struct ModListFiltersTests {

    private func paged() -> ModListFilters {
        var filters = ModListFilters()
        filters.page = 4
        return filters
    }

    // MARK: - Chaque filtre ramène à la page 1

    @Test func searchChangeResetsPage() {
        var filters = paged()
        filters.search = "SVE"
        #expect(filters.page == 1)
    }

    @Test func scopeChangeResetsPage() {
        var filters = paged()
        filters.scope = .issues
        #expect(filters.page == 1)
    }

    @Test func categoryChangeResetsPage() {
        var filters = paged()
        filters.category = .category(NexusCategory.all[0])
        #expect(filters.page == 1)
    }

    @Test func configOnlyChangeResetsPage() {
        var filters = paged()
        filters.configOnly = true
        #expect(filters.page == 1)
    }

    @Test func favoritesOnlyChangeResetsPage() {
        var filters = paged()
        filters.favoritesOnly = true
        #expect(filters.page == 1)
    }

    @Test func blacklistedOnlyChangeResetsPage() {
        var filters = paged()
        filters.blacklistedOnly = true
        #expect(filters.page == 1)
    }

    @Test func frenchTranslationChangeResetsPage() {
        var filters = paged()
        filters.frenchTranslation = .partial
        #expect(filters.page == 1)
    }

    // MARK: - Le tri, lui, ne change pas le nombre de résultats

    @Test func sortChangeKeepsThePage() {
        var filters = paged()
        filters.sort = .author
        #expect(filters.page == 4)
    }

    // MARK: - La même valeur ne déclenche rien

    @Test func reassigningIdenticalValueKeepsThePage() {
        var filters = paged()
        filters.scope = .all          // déjà `.all`
        filters.search = ""           // déjà vide
        #expect(filters.page == 4)
    }

    // MARK: - focus(on:) : tout filtre susceptible d'écarter est levé

    @Test func focusLiftsEveryFilterAndResetsPage() {
        var filters = ModListFilters()
        filters.scope = .disabled
        filters.category = .uncategorized
        filters.configOnly = true
        filters.favoritesOnly = true
        filters.blacklistedOnly = true
        filters.frenchTranslation = .stale
        filters.search = "ancienne"
        filters.page = 12

        filters.focus(on: "Ridgeside")

        #expect(filters.scope == .all)
        #expect(filters.category == .all)
        #expect(!filters.configOnly)
        #expect(!filters.favoritesOnly)
        #expect(!filters.blacklistedOnly)
        #expect(filters.frenchTranslation == .off)
        #expect(filters.search == "Ridgeside")
        #expect(filters.page == 1)
    }

    /// Le cas que la ligne `page = 1` explicite de `focus` est seule à couvrir :
    /// sauter deux fois vers le **même** mod laisse `search` inchangé, son
    /// `didSet` ne se déclenche pas — sans cette ligne, on resterait sur une
    /// page où le mod n'est pas.
    @Test func focusTwiceOnTheSameTermStillResetsPage() {
        var filters = ModListFilters()
        filters.focus(on: "SVE")
        filters.page = 9
        filters.focus(on: "SVE")
        #expect(filters.page == 1)
    }
}
