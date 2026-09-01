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

    var onURL: ((URL) -> Void)?

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
        guard let handler = onURL, !pendingURLs.isEmpty else { return }
        let buffered = pendingURLs
        pendingURLs.removeAll()
        buffered.forEach(handler)
    }
}

@main
struct StarHubTHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = StarHubTHViewModel()

    init() {
        if let currentLang = UserDefaults.standard.string(forKey: UDKey.currentLanguage) {
            UserDefaults.standard.set([currentLang], forKey: UDKey.appleLanguagesOverride)
        }
    }

    var body: some Scene {
        // A single `Window` (not `WindowGroup`): macOS never spawns a second
        // window for it, so an nxm:// activation just brings this one forward
        // instead of stacking duplicates.
        Window("StarHubFR", id: "main") {
            MainView(vm: vm)
                .onAppear {
                    // Route nxm:// links (buffered at cold launch) into the
                    // single shared ViewModel.
                    appDelegate.onURL = { [vm] url in vm.handleNxmURL(url) }
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
                        // `.onChange` ci-dessous ne se déclenchera jamais, et
                        // un lien en attente resterait sans réponse.
                        appDelegate.deliverPendingURLs()
                    }
                }
                // The splash lives in its own window now, so there's no
                // half-loaded UI on screen to protect: the native menus can
                // stay as they are.
                .onChange(of: vm.isLaunching) { _, isLaunching in
                    if !isLaunching {
                        LaunchSplashController.shared.finish()
                        // Après `finish()`, jamais avant : la feuille
                        // d'installation qu'un lien `nxm://` finit par ouvrir
                        // a besoin d'une fenêtre principale à l'écran pour s'y
                        // attacher — et pour pouvoir être refermée.
                        appDelegate.deliverPendingURLs()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
