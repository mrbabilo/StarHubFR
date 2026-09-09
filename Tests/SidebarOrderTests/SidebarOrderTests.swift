import Testing
@testable import StarHubTHCore

@Suite("Ordre de la barre latérale")
struct SidebarOrderTests {

    /// Les 15 destinations, dans l'ordre relevé à l'écran le 2026-09-09.
    /// Écrit une fois ici, relu par les tests d'ordre et de couverture.
    private static let attendu: [SidebarDestination] = [
        .home, .mods, .discover, .updates, .profiles, .saves,
        .systemAlerts, .quarantine, .installBackups, .configBackups,
        .maintenance, .logs, .settings, .appChangelog, .thaiHub,
    ]

    /// Non-régression : sans ce test, un réordonnancement silencieux passerait
    /// — et décalerait ⌘1…⌘9.
    @Test func lOrdreEstCeluiDeLEcran() {
        #expect(SidebarOrder.all.map(\.destination) == Self.attendu)
    }

    /// Le compilateur garantit qu'une destination a une page (F7), pas
    /// qu'elle est dans ce tableau : c'est ce test qui le tient.
    @Test func lesQuinzeDestinationsSontToutesPresentes() {
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

    @Test func leHubThaiEstConditionnelEtDernier() {
        #expect(SidebarOrder.all.last?.destination == .thaiHub)
        #expect(SidebarOrder.visible(showThaiHub: true).count == 15)
        #expect(SidebarOrder.visible(showThaiHub: false).count == 14)
        #expect(!SidebarOrder.visible(showThaiHub: false)
            .contains { $0.destination == .thaiHub })
    }

    @Test func lesNeufPremieresVisiblesPortentUnNumero() {
        #expect(SidebarOrder.shortcutIndex(of: .home, showThaiHub: false) == 1)
        #expect(SidebarOrder.shortcutIndex(of: .mods, showThaiHub: false) == 2)
        #expect(SidebarOrder.shortcutIndex(of: .installBackups, showThaiHub: false) == 9)
    }

    @Test func laDixiemeNAPasDeNumero() {
        #expect(SidebarOrder.shortcutIndex(of: .configBackups, showThaiHub: false) == nil)
        #expect(SidebarOrder.shortcutIndex(of: .thaiHub, showThaiHub: true) == nil)
    }

    /// Le hub thaï est dernier : l'activer ne doit décaler aucun numéro.
    @Test func activerLeHubThaiNeDecaleAucunRaccourci() {
        for d in SidebarOrder.visible(showThaiHub: false).map(\.destination) {
            #expect(SidebarOrder.shortcutIndex(of: d, showThaiHub: false)
                    == SidebarOrder.shortcutIndex(of: d, showThaiHub: true))
        }
    }

    @Test func allerRetourEntreNumeroEtDestination() {
        for n in 1...9 {
            let e = SidebarOrder.entry(forShortcut: n, showThaiHub: false)
            #expect(e != nil, "⌘\(n) ne mène nulle part")
            if let e {
                #expect(SidebarOrder.shortcutIndex(of: e.destination,
                                                   showThaiHub: false) == n)
            }
        }
        #expect(SidebarOrder.entry(forShortcut: 10, showThaiHub: false) == nil)
        #expect(SidebarOrder.entry(forShortcut: 0, showThaiHub: false) == nil)
    }

    @Test func lesGroupesSuiventLOrdreDeLEcran() {
        #expect(SidebarOrder.entries(in: .top, showThaiHub: false)
            .map(\.destination) == [.home])
        #expect(SidebarOrder.entries(in: .library, showThaiHub: false)
            .map(\.destination) == [.mods, .discover, .updates])
        #expect(SidebarOrder.entries(in: .saves, showThaiHub: false)
            .map(\.destination) == [.profiles, .saves])
        #expect(SidebarOrder.entries(in: .health, showThaiHub: false)
            .map(\.destination) == [.systemAlerts, .quarantine,
                                    .installBackups, .configBackups, .maintenance])
        #expect(SidebarOrder.entries(in: .app, showThaiHub: false)
            .map(\.destination) == [.logs, .settings, .appChangelog])
    }

    /// Les clés doivent être celles déjà en place — aucune clé de destination
    /// n'est créée par ce lot (relevé le 2026-09-09).
    @Test func lesClesSontCellesDejaEnPlace() {
        func cle(_ d: SidebarDestination) -> String? {
            SidebarOrder.all.first { $0.destination == d }?.labelKey
        }
        #expect(cle(.home) == "main_home")
        #expect(cle(.mods) == "mods_mods")
        #expect(cle(.thaiHub) == "thaihub_title")
        #expect(cle(.configBackups) == "mod_config_backups_tab_title")
    }
}
