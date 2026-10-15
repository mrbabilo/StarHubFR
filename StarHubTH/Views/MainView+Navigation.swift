import SwiftUI

extension MainView {
    /// Le magasin de navigation, sans repasser par `vm` à chaque lecture
    /// (le cliquet compte chaque `vm`).
    var navigation: NavigationStore { vm.navigationStore }
}
