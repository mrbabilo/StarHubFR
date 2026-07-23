import SwiftUI

/// Handles incoming `nxm://` deep links at the AppKit level.
///
/// Using SwiftUI's `WindowGroup { ….onOpenURL { } }` spawns a NEW window for
/// every incoming URL on macOS — clicking "Mod Manager Download" repeatedly
/// stacked extra windows instead of routing to the existing one. Handling the
/// URL through `application(_:open:)` delivers it to the single running
/// instance without creating a window; SwiftUI never sees a URL activation.
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
        WindowGroup {
            MainView(vm: vm)
                .onAppear {
                    // Route nxm:// links (buffered at cold launch) into the
                    // single shared ViewModel — no extra windows.
                    appDelegate.onURL = { [vm] url in vm.handleNxmURL(url) }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
