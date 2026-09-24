import Testing
@testable import StarHubTHCore

@Suite("Ordre de la barre latérale")
struct SidebarOrderTests {

    /// Les 14 destinations, dans l'ordre de l'écran. Relevé le 2026-09-09 ;
    /// le 2026-09-24 (C5-T1), « Traductions FR » entre en Bibliothèque et le
    /// hub thaï, conditionnel et dernier, sort ; puis (I-T8) les sauvegardes
    /// d'installation et de configuration fusionnent en « Sauvegardes ».
    /// Écrit une fois ici, relu par les tests d'ordre et de couverture.
    private static let attendu: [SidebarDestination] = [
        .home, .mods, .discover, .updates, .frenchTranslations, .profiles, .saves,
        .systemAlerts, .quarantine, .backups,
        .maintenance, .logs, .settings, .appChangelog,
    ]

    /// Non-régression : sans ce test, un réordonnancement silencieux passerait
    /// — et décalerait ⌘1…⌘9.
    @Test func lOrdreEstCeluiDeLEcran() {
        #expect(SidebarOrder.all.map(\.destination) == Self.attendu)
    }

    /// Le compilateur garantit qu'une destination a une page (F7), pas
    /// qu'elle est dans ce tableau : c'est ce test qui le tient.
    @Test func lesQuatorzeDestinationsSontToutesPresentes() {
        for d in Self.attendu {
            #expect(SidebarOrder.all.contains { $0.destination == d },
                    "\(d) manque à SidebarOrder.all")
        }
    }

    @Test func aucuneDestinationEnDouble() {
        let vues = SidebarOrder.all.map(\.destination)
        #expect(Set(vues).count == vues.count)
    }

    @Test func chaqueEntreePorteUneIconeEtUneCle() {
        for e in SidebarOrder.all {
            #expect(!e.icon.isEmpty, "\(e.destination) sans icône")
            #expect(!e.labelKey.isEmpty, "\(e.destination) sans clé")
        }
    }

    /// C5-T1 décale d'un rang tout ce qui suit « Mises à jour » : la
    /// quarantaine prend ⌘9, les sauvegardes n'ont pas de numéro (I-T8 les
    /// place après elle pour ne pas décaler ⌘8/⌘9).
    @Test func lesNeufPremieresPortentUnNumero() {
        #expect(SidebarOrder.shortcutIndex(of: .home) == 1)
        #expect(SidebarOrder.shortcutIndex(of: .mods) == 2)
        #expect(SidebarOrder.shortcutIndex(of: .frenchTranslations) == 5)
        #expect(SidebarOrder.shortcutIndex(of: .quarantine) == 9)
    }

    @Test func laDixiemeNAPasDeNumero() {
        #expect(SidebarOrder.shortcutIndex(of: .backups) == nil)
    }

    @Test func allerRetourEntreNumeroEtDestination() {
        for n in 1...9 {
            let e = SidebarOrder.entry(forShortcut: n)
            #expect(e != nil, "⌘\(n) ne mène nulle part")
            if let e {
                #expect(SidebarOrder.shortcutIndex(of: e.destination) == n)
            }
        }
        #expect(SidebarOrder.entry(forShortcut: 10) == nil)
        #expect(SidebarOrder.entry(forShortcut: 0) == nil)
    }

    @Test func lesGroupesSuiventLOrdreDeLEcran() {
        #expect(SidebarOrder.entries(in: .top).map(\.destination) == [.home])
        #expect(SidebarOrder.entries(in: .library).map(\.destination)
                == [.mods, .discover, .updates, .frenchTranslations])
        #expect(SidebarOrder.entries(in: .saves).map(\.destination) == [.profiles, .saves])
        #expect(SidebarOrder.entries(in: .health).map(\.destination)
                == [.systemAlerts, .quarantine, .backups, .maintenance])
        #expect(SidebarOrder.entries(in: .app).map(\.destination)
                == [.logs, .settings, .appChangelog])
    }

    /// Les clés des destinations d'origine restent celles relevées le
    /// 2026-09-09 ; « Traductions FR » porte la sienne.
    @Test func lesClesSontCellesAttendues() {
        func cle(_ d: SidebarDestination) -> String? {
            SidebarOrder.all.first { $0.destination == d }?.labelKey
        }
        #expect(cle(.home) == "main_home")
        #expect(cle(.mods) == "mods_mods")
        #expect(cle(.frenchTranslations) == "frtr_title")
        #expect(cle(.backups) == "mod_install_manage_backups")
    }
}
