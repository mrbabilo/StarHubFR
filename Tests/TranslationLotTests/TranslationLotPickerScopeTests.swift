import Testing
@testable import StarHubTHCore

struct TranslationLotPickerScopeTests {
    private func mod(_ name: String, folderName: String) -> ModItem {
        ModItem(uniqueId: "Test.\(folderName)", name: name, folderName: folderName,
                version: "1.0.0", author: "Test", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: true, dependencies: [])
    }

    /// Une régression vers la collection complète ferait réapparaître
    /// `Lookup Anything` dans chacun des deux résultats filtrés.
    @Test func searchNarrowsVisibleModsByNameOrFolder() {
        let mods = [mod("Seasonal Outfits", folderName: "Poltergeister.Seasonal"),
                    mod("Stardew Valley Expanded", folderName: "FlashShifter.SVE"),
                    mod("Lookup Anything", folderName: "Pathoschild.LookupAnything")]

        let byName = TranslationLotPickerScope.visibleMods(in: mods, searchText: "VALLEY")
        let byFolder = TranslationLotPickerScope.visibleMods(in: mods, searchText: "seasonal")
        let noMatch = TranslationLotPickerScope.visibleMods(in: mods, searchText: "absent")
        let cleared = TranslationLotPickerScope.visibleMods(in: mods, searchText: "")

        #expect(byName.map(\.folderName) == ["FlashShifter.SVE"])
        #expect(byFolder.map(\.folderName) == ["Poltergeister.Seasonal"])
        #expect(noMatch.isEmpty)
        #expect(cleared.map(\.folderName) == mods.map(\.folderName))
    }

    /// Le compteur d'une recherche décrit les lignes affichées, pas les
    /// sélections cachées appartenant au reste de la modlist.
    @Test func checkedCountIsScopedToVisibleMods() {
        let visible = [mod("Seasonal Outfits", folderName: "Poltergeister.Seasonal")]
        let checked: Set<String> = ["Poltergeister.Seasonal", "Pathoschild.LookupAnything"]

        #expect(TranslationLotPickerScope.checkedCount(in: visible, checked: checked) == 1)
    }
}
