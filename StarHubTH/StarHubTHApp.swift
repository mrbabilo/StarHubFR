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

/// Holds the saved main menu so it can be restored after the launch splash.
///
/// SwiftUI rebuilds the menu bar on the `Window` scene's behalf; saving the
/// AppKit-level `NSApp.mainMenu` reference and reassigning it after launch is
/// the most reliable way to get the exact same menus back. Setting it to
/// `nil` hides BOTH the visible menus AND their keyboard shortcuts, which is
/// what we want while the splash overlay is up — no Cmd+W / Cmd+R etc.
/// acting on a half-loaded UI.
private final class LaunchMenuState {
    static let shared = LaunchMenuState()
    var savedMenu: NSMenu?
    private init() {}
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
                    // Hide native menus from the very first frame. `onChange`
                    // below would miss the initial state (isLaunching starts
                    // true and only fires on change), so we also hide here.
                    if vm.isLaunching, NSApp.mainMenu != nil {
                        LaunchMenuState.shared.savedMenu = NSApp.mainMenu
                        NSApp.mainMenu = nil
                    }
                }
                // Hide macOS native menus (File / Edit / View / Window / Help)
                // for the duration of the launch splash. Setting
                // `NSApp.mainMenu = nil` removes both the visible menus AND
                // their keyboard shortcuts — no Cmd+W / Cmd+R etc. can act on
                // the half-loaded UI. The original menu is saved first and
                // restored verbatim once `isLaunching` flips to false.
                .onChange(of: vm.isLaunching) { _, isLaunching in
                    if isLaunching {
                        if NSApp.mainMenu != nil {
                            LaunchMenuState.shared.savedMenu = NSApp.mainMenu
                            NSApp.mainMenu = nil
                        }
                    } else if NSApp.mainMenu == nil, let saved = LaunchMenuState.shared.savedMenu {
                        NSApp.mainMenu = saved
                        LaunchMenuState.shared.savedMenu = nil
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
