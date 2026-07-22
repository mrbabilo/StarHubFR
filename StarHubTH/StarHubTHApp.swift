import SwiftUI

@main
struct StarHubTHApp: App {
    init() {
        if let currentLang = UserDefaults.standard.string(forKey: "currentLanguage") {
            UserDefaults.standard.set([currentLang], forKey: "AppleLanguages")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
