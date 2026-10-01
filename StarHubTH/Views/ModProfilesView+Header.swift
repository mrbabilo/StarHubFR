import SwiftUI

extension ModProfilesView {
    /// « 3 profils · actif : Principal » — ce qui est chargé se lit avant la
    /// liste (en-tête de page, audit UX 2026-10-02).
    var headerSummary: String {
        let count = Int64(vm.modProfiles.count)
        guard let active = vm.activeProfile else {
            return String(format: localization.L(L10n.Profiles.headerNoneActive), count)
        }
        return String(format: localization.L(L10n.Profiles.headerSummary), count, active.name)
    }
}
