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

@main
struct StarHubTHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = StarHubTHViewModel()

    init() {
        if let currentLang = UserDefaults.standard.string(forKey: "currentLanguage") {
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
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
