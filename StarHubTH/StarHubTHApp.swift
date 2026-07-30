import SwiftUI

/// Handles incoming `nxm://` deep links at the AppKit level.
///
/// The URL is delivered through `application(_:open:)` rather than SwiftUI's
/// `.onOpenURL`, so no SwiftUI URL activation fires. Combined with a single
/// `Window` scene (not `WindowGroup`), clicking "Mod Manager Download"
/// repeatedly routes into the one existing window instead of stacking new ones.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs delivered before the SwiftUI view wired up its handler — e.g. a
    /// cold launch triggered by an nxm:// click — are buffered, then flushed
    /// once `onURL` is assigned.
    private var pendingURLs: [URL] = []

    var onURL: ((URL) -> Void)? {
        didSet {
            guard onURL != nil, !pendingURLs.isEmpty else { return }
            let buffered = pendingURLs
            pendingURLs.removeAll()
            buffered.forEach { onURL?($0) }
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
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "nxm" {
            if let handler = onURL {
                handler(url)
            } else {
                pendingURLs.append(url)
            }
        }
    }
}

@main
struct StarHubTHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = StarHubTHViewModel()

    init() {
        if let currentLang = UserDefaults.standard.string(forKey: UDKey.currentLanguage) {
            UserDefaults.standard.set([currentLang], forKey: "AppleLanguages")
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
                    // Raise the splash now. The main window was already
                    // intercepted in `applicationWillFinishLaunching`, so it
                    // never reached the screen — no need to defer this.
                    if vm.isLaunching {
                        LaunchSplashController.shared.show(vm: vm)
                    }
                }
                // The splash lives in its own window now, so there's no
                // half-loaded UI on screen to protect: the native menus can
                // stay as they are.
                .onChange(of: vm.isLaunching) { _, isLaunching in
                    if !isLaunching {
                        LaunchSplashController.shared.finish()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
