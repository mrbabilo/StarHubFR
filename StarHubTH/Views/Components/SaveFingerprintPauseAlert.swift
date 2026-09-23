import SwiftUI

/// A1-T8 — l'avertissement d'empreintes de sauvegarde, branché au niveau
/// racine (`MainView`) : une page d'onglet mourrait au changement de page —
/// `MainView` remet ses états de détail à nil — pendant que la bascule
/// resterait suspendue. L'état vit dans `SaveFingerprintPauseStore` ; ici,
/// l'écran.
///
/// Même patron que `conflictActivationGate` : l'alerte n'active rien
/// d'elle-même — confirmer reprend la bascule suspendue, annuler la
/// clôture sans renommer. Lecture seule : elle chiffre ce que les saves
/// réelles portent et laisse la décision à l'utilisateur — aucun crash
/// observé sur le parc pour ces empreintes (objets référencés par id, pas
/// des types C#), le texte ne dit donc pas « danger », il dit « voilà ce
/// qui restera ».
extension View {
    func saveFingerprintPauseGate(vm: StarHubTHViewModel) -> some View {
        let store = vm.saveFingerprintPauseStore
        let localization = vm.localization
        return alert(
            localization.L(L10n.Mods.fingerprintPauseTitle),
            isPresented: Binding(
                get: { store.pending != nil },
                // La fermeture par Esc / bouton extérieur vaut annulation —
                // idempotent : après un confirm, le store est déjà au repos.
                set: { if !$0 { store.cancel() } }
            )
        ) {
            Button(localization.L(L10n.Mods.fingerprintPauseConfirm)) {
                store.confirm()
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) {
                store.cancel()
            }
        } message: {
            if let pending = store.pending {
                Text(FingerprintSummary.text(
                    modName: pending.mod.name,
                    report: pending.report,
                    localization: localization))
            }
        }
    }
}

/// Le texte du message : « Mettre en pause n'efface pas ce que %@ a
/// laissé… » + une ligne par save — les plus chargées d'abord, les familles
/// nulles tuées, et une retenue au-delà de trois saves. Le nombre de saves
/// est arbitraire : une alerte qui déroulerait vingt lignes serait
/// illisible (et son message tronqué par l'OS).
private enum FingerprintSummary {
    static func text(
        modName: String,
        report: SaveFingerprintReport,
        localization: LocalizationStore
    ) -> String {
        let limite = 3
        var lignes = report.sortedEntries.prefix(limite).map { entry -> String in
            var familles: [String] = []
            if entry.counts.objects > 0 {
                familles.append(String(
                    format: localization.L(L10n.Mods.fingerprintObjects),
                    entry.counts.objects))
            }
            if entry.counts.buildings > 0 {
                familles.append(String(
                    format: localization.L(L10n.Mods.fingerprintBuildings),
                    entry.counts.buildings))
            }
            if entry.counts.modDataKeys > 0 {
                familles.append(String(
                    format: localization.L(L10n.Mods.fingerprintDataKeys),
                    entry.counts.modDataKeys))
            }
            return String(
                format: localization.L(L10n.Mods.fingerprintSaveLine),
                entry.name, familles.joined(separator: " · "))
        }
        let cachées = report.hiddenCount(beyond: limite)
        if cachées > 0 {
            lignes.append(String(
                format: localization.L(L10n.Mods.fingerprintMoreSaves), cachées))
        }
        return String(
            format: localization.L(L10n.Mods.fingerprintPauseMessage), modName)
            + "\n" + lignes.joined(separator: "\n")
    }
}
