import SwiftUI

extension UpdatesView {
    /// `rate_limited` et `server_down` sont nommés par `NexusUpdateCheck` ;
    /// le reste est un message générique.
    func checkErrorText(_ err: String) -> String {
        switch err {
        case "rate_limited": return localization.L(L10n.Updates.nexusRateLimited)
        case "server_down": return localization.L(L10n.Updates.smapiServerDown)
        default: return localization.L(L10n.Updates.nexusError)
        }
    }
}
