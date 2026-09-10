import SwiftUI

/// Handles incoming `nxm://` deep links at the AppKit level.
///
/// The URL is delivered through `application(_:open:)` rather than SwiftUI's
/// `.onOpenURL`, so no SwiftUI URL activation fires. Combined with a single
/// `Window` scene (not `WindowGroup`), clicking "Mod Manager Download"
/// repeatedly routes into the one existing window instead of stacking new ones.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs delivered before l'app est prête — typiquement un lancement à froid
    /// déclenché par un clic `nxm://` — sont mises en attente, puis délivrées
    /// par `deliverPendingURLs()`.
    private var pendingURLs: [URL] = []

    /// Faux tant que le lancement n'est pas terminé.
    ///
    /// Un lien `nxm://` déclenche un téléchargement puis **la feuille
    /// d'installation**. Délivré dès que `onURL` était assigné — c'est-à-dire
    /// depuis le `.onAppear` de `MainView`, alors que le splash est encore à
    /// l'écran et la fenêtre principale masquée — la feuille se présentait sur
    /// une fenêtre absente : elle s'affichait sans pouvoir être fermée, et la
    /// fenêtre principale restait inatteignable. On attend donc la révélation.
    private var isReady = false

    var onURL: ((URL) -> Void)? {
        didSet {
            // Un handler qui arrive après `deliverPendingURLs()` (isReady
            // déjà levé, handler encore absent à ce moment-là) ne doit pas
            // laisser mourir la queue. On ne flushe QUE si prêt : livrer
            // avant la révélation de la fenêtre principale rouvrirait le
            // bug de la feuille orpheline documenté sur `isReady`.
            guard isReady else { return }
            flushPendingURLs()
        }
    }

    /// Keeps the app alive while the main window is hidden behind the launch
    /// splash. Hiding it (`orderOut`) otherwise reads as "the last window
    /// closed" — the borderless splash panel doesn't count — and macOS
    /// terminates the app a moment after launch.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Claims the main window before macOS ever puts it on screen.
    ///
    /// Hiding it from SwiftUI's `.onAppear` is already too late: the window has
    /// been presented by then, so it flashes for a frame before being ordered
    /// out. This runs before any window is displayed, and watches for the
    /// window's creation so it can be hidden the instant it exists.
    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchSplashController.shared.claimMainWindowBeforeItAppears()
        // Ceinture et bretelles : l'instance est vierge à ce point (un
        // `application(_:open:)` ne peut pas précéder ce callback dans un
        // même processus), mais rendre l'invariant explicite garantit qu'un
        // `nxm://` livré très tôt ne trouve jamais `isReady == true` ni une
        // queue résiduelle, même si l'ordre d'appel changeait un jour.
        isReady = false
        pendingURLs.removeAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "nxm" {
            if isReady, let handler = onURL {
                handler(url)
            } else {
                pendingURLs.append(url)
            }
        }
    }

    /// Délivre les liens mis en attente, une fois la fenêtre principale à
    /// l'écran. Idempotent : appelé depuis les deux chemins de fin de
    /// lancement (le `.onChange` habituel, et le `.onAppear` d'un lancement
    /// déjà terminé), et sans effet quand rien n'attend.
    func deliverPendingURLs() {
        isReady = true
        flushPendingURLs()
    }

    /// Vide la queue vers le handler présent, sans toucher à `isReady`.
    private func flushPendingURLs() {
        guard let handler = onURL, !pendingURLs.isEmpty else { return }
        let buffered = pendingURLs
        pendingURLs.removeAll()
        buffered.forEach(handler)
    }
}

@main
struct StarHubTHApp: App {
    /// **Avant tout le reste.** Changer l'identifiant de bundle change le
    /// domaine `UserDefaults` : sans reprise, l'app se réveillerait sans
    /// dossier de jeu, sans profils et sans registre d'installation.
    ///
    /// Le travail vit dans `DefaultsMigration.runOnce`, déclenché **aussi**
    /// depuis `AppSupport.resolve()`. Cet appel-ci n'est donc plus porteur de
    /// l'ordre — il ne l'a jamais prouvé, et une revue a montré ce qu'un
    /// ordre supposé coûtait : si le ViewModel gagnait la course, il semait un
    /// profil par défaut, et la reprise s'abstenait ensuite (« la destination
    /// a déjà une valeur »), laissant les vrais profils orphelins dans
    /// l'ancien plist. La reprise est idempotente : deux déclencheurs, un seul
    /// effet.
    private let bootstrapDefaults = DefaultsMigration.runOnce

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // La langue d'interface appartient à l'App (REFACTORING §6, domaine
    // Localisation) : les menus de `CommandMenu` résolvent leurs libellés
    // avant toute vue, ils observent la source elle-même. Le ViewModel la
    // reçoit à l'init et ne la possède pas.
    @StateObject private var localization: LocalizationStore
    @StateObject private var vm: StarHubTHViewModel
    @AppStorage("showThaiTranslationHub") private var showThaiHub = false

    init() {
        // Une seule instance du store, habillée deux fois : les menus et le
        // VM doivent observer le même objet, et un `@StateObject` ne peut pas
        // lire un autre `@StateObject` de la même struct dans son init.
        let store = LocalizationStore()
        _localization = StateObject(wrappedValue: store)
        _vm = StateObject(wrappedValue: StarHubTHViewModel(localization: store))
        // currentLanguage (désormais `LocalizationStore`) reste l'unique
        // source de vérité. Son didSet resynchronise `AppleLanguages` (via
        // UDKey.appleLanguagesOverride) — aucune écriture à faire ici.
    }

    var body: some Scene {
        // A single `Window` (not `WindowGroup`): macOS never spawns a second
        // window for it, so an nxm:// activation just brings this one forward
        // instead of stacking duplicates.
        Window("StarHubFR", id: AppWindowID.main) {
            MainView(vm: vm, localization: localization)
                .onAppear {
                    // Route nxm:// links (buffered at cold launch) into the
                    // single shared ViewModel.
                    appDelegate.onURL = { [vm] url in vm.handleNxmURL(url) }
                    // X65 — la livraison suit la **révélation de la fenêtre**,
                    // et rien d'autre. Elle était recopiée sur deux des trois
                    // chemins qui révèlent ; le troisième, le filet de sécurité
                    // des 30 s, l'oubliait. Posé avant tout `finish()`, y
                    // compris celui de la branche ci-dessous.
                    LaunchSplashController.shared.onReveal = { [appDelegate, vm] in
                        appDelegate.deliverPendingURLs()
                        // L'état d'À propos, puis le check — asynchrones :
                        // l'alerte arrive quand elle arrive, la *demande*
                        // suit la révélation de la fenêtre (leçon X65).
                        vm.loadLastKnownRelease()
                        vm.checkForAppRelease()
                    }
                    // Une recherche laissée en plan (app quittée ou plantée en
                    // cours de bissection) ? Le signaler dès le démarrage.
                    vm.bisection.checkForInterruptedSession()
                    // Raise the splash now. The main window was already
                    // intercepted in `applicationWillFinishLaunching`, so it
                    // never reached the screen — no need to defer this.
                    if vm.isLaunching {
                        LaunchSplashController.shared.show(vm: vm)
                    } else {
                        // Lancement déjà terminé quand la vue paraît : le
                        // `.onChange` ci-dessous ne se déclenchera jamais.
                        //
                        // `finish()` d'abord, et pas seulement la livraison des
                        // liens : c'est lui qui détache l'observateur posé par
                        // `claimMainWindowBeforeItAppears`, lequel masque la
                        // fenêtre principale à chaque fois qu'elle devient
                        // visible. Sans lui, ce chemin laisse une app sans
                        // aucune fenêtre — et que
                        // `applicationShouldTerminateAfterLastWindowClosed`
                        // empêche de se refermer d'elle-même.
                        //
                        // Aujourd'hui inatteignable : `isLaunching` ne retombe
                        // qu'après un `DispatchQueue.global` suivi d'un
                        // `asyncAfter(0.15)`, bien après ce `.onAppear`. La
                        // branche ne dépend plus de ce délai pour être sûre.
                        // `finish()` est idempotent et documenté comme sûr
                        // avant tout `show()`. Il délivre lui-même les liens
                        // en attente, via `onReveal` posé ci-dessus.
                        LaunchSplashController.shared.finish()
                        // R2 : la fenêtre est révélée — c'est le moment de
                        // présenter le dialogue de reprise, s'il y en a un.
                        vm.surfaceApplyRecoveryIfNeeded()
                    }
                }
                // The splash lives in its own window now, so there's no
                // half-loaded UI on screen to protect: the native menus can
                // stay as they are.
                .onChange(of: vm.isLaunching) { _, isLaunching in
                    if !isLaunching {
                        // `finish()` révèle la fenêtre **puis** délivre les
                        // liens en attente, dans cet ordre : la feuille
                        // d'installation qu'un lien `nxm://` finit par ouvrir a
                        // besoin d'une fenêtre principale à l'écran pour s'y
                        // attacher — et pour pouvoir être refermée.
                        LaunchSplashController.shared.finish()
                        // R2 : la fenêtre est révélée — même point que la
                        // livraison des liens nxm://. Un dialogue présenté
                        // pendant le splash ne s'afficherait pas.
                        vm.surfaceApplyRecoveryIfNeeded()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
        // Le menu « Aller » — I-T1/I-T2. Les raccourcis deviennent visibles, et
        // macOS les gère nativement.
        //
        // ⚠️ Ce code vit dans la **scène App** : il ne peut écrire aucun
        // `@State` de MainView. Il n'appelle donc que les canaux du ViewModel.
        .commands {
            CommandMenu(localization.L(L10n.Palette.goMenu)) {
                // Construits depuis SidebarOrder — jamais réécrits ici, sinon
                // le menu et la barre divergeraient au premier ajout.
                ForEach(1...9, id: \.self) { n in
                    if let e = SidebarOrder.entry(forShortcut: n,
                                                  showThaiHub: showThaiHub) {
                        Button(localization.L(e.labelKey)) { vm.requestTab(e.destination) }
                            .keyboardShortcut(KeyEquivalent(Character("\(n)")),
                                              modifiers: .command)
                    }
                }
                Divider()
                Button(localization.L(L10n.Palette.open)) { vm.requestPalette() }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        // Le bilan post-installation — une fenêtre dédiée, redimensionnable,
        // là où l'écran de succès interne de la feuille vivait. Ouverte par
        // `openWindow(id:)` depuis MainView quand un report est posé ; une
        // seconde ouverture l'amène au premier plan et remplace le contenu.
        Window(localization.L(L10n.InstallReport.windowTitle), id: AppWindowID.installReport) {
            InstallReportWindow(vm: vm, localization: localization)
        }
        .windowResizability(.contentMinSize)
    }
}
