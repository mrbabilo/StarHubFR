import Testing
@testable import StarHubTHCore

@Suite("Écran d'aide des raccourcis")
struct KeyboardShortcutCatalogTests {
    private let groups = KeyboardShortcutCatalog.groups()

    /// ⌘1…⌘9 viennent de SidebarOrder, pas d'une copie : l'aide et le menu
    /// « Aller » annoncent la même destination pour le même chiffre.
    @Test func lesChiffresSuiventLeMenuAller() {
        let screens = groups.first { $0.titleKey == L10n.Shortcuts.groupScreens }?.entries ?? []
        #expect(screens.count == 9)
        for n in 1...9 {
            let entry = screens.first { $0.keys == ["⌘", "\(n)"] }
            #expect(entry?.labelKey == SidebarOrder.entry(forShortcut: n)?.labelKey)
        }
    }

    /// La liste figée : un raccourci ajouté ou retiré ailleurs doit l'être
    /// ici aussi, et ce test le rappelle au relecteur.
    @Test func laListeEstCelleQueLAppCable() {
        let combos = groups.flatMap(\.entries).map { $0.keys.joined(separator: " ") }
        #expect(combos.contains("⌘ K"))
        #expect(combos.contains("⌘ F"))
        #expect(combos.contains("⌘ /"))
        #expect(combos.contains("↑ | ↓"))
        #expect(groups.flatMap(\.entries).count == 9 + 4 + 3 + 3 + 2 + 3)
    }

    /// Dans un même groupe, une combinaison ne peut pas vouloir dire deux
    /// choses.
    @Test func pasDeCombinaisonEnDoubleDansUnGroupe() {
        for g in groups {
            let combos = g.entries.map { $0.keys.joined() }
            #expect(Set(combos).count == combos.count, "doublon dans \(g.titleKey)")
        }
    }
}
