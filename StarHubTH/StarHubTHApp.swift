import SwiftUI

@main
struct StarHubTHApp: App {
    init() {
        if let currentLang = UserDefaults.standard.string(forKey: "currentLanguage") {
            UserDefaults.standard.set([currentLang], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowResizability(.contentSize)
    }
}
