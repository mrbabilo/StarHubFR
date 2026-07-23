import SwiftUI

@main
struct StarHubTHApp: App {
    @StateObject private var vm = StarHubTHViewModel()

    init() {
        if let currentLang = UserDefaults.standard.string(forKey: "currentLanguage") {
            UserDefaults.standard.set([currentLang], forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView(vm: vm)
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "nxm" {
                        vm.handleNxmURL(url)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
