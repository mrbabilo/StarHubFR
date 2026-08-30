import SwiftUI

/// Les actions de la fiche (H-T4b) : l'état en bouton bleu proéminant (P5),
/// le reste en `.bordered`, la suppression à l'écart. Réservée au premier
/// niveau — un composant de pack ne se pilote pas seul (règle de domaine).
///
/// Les portes d'activation (compatibilité smapi.io, conflit A5) restent
/// portées par la fiche : la barre arme `pendingActivation`/`pendingConflict`
/// par bindings, les modificateurs qui les consomment décorent le body de
/// `ModDetailView`. Le signalement et la suppression sont des closures pour
/// la même raison — feuille et confirmation y vivent.
struct ModDetailActionBar: View {
    @ObservedObject var vm: StarHubTHViewModel
    /// La copie figée à l'ouverture — pour l'identité (dossier, libellés).
    let mod: ModItem
    @Binding var pendingActivation: ModItem?
    @Binding var pendingConflict: ConflictActivation?
    let onReportConflict: () -> Void
    let onDelete: () -> Void

    /// L'état relu à chaque rendu : la pause renomme le dossier physique,
    /// la copie figée ne suit pas.
    private var live: ModItem {
        vm.mods.first { $0.folderName == mod.folderName } ?? mod
    }

    var body: some View {
        HStack(spacing: 12) {
            stateButton

            // Le favori : même geste de tri du parc, et la fiche est l'écran
            // où l'on décide du sort d'un mod. `live` pour rester d'accord
            // avec la liste après un aller-retour.
            Button {
                vm.toggleFavorite(live)
            } label: {
                Label(vm.L(vm.isFavorite(live) ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd),
                      systemImage: vm.isFavorite(live) ? "star.fill" : "star")
            }
            .buttonStyle(.bordered)
            .foregroundColor(vm.isFavorite(live) ? .yellow : .secondary)
            .pointingHandCursor()

            // La config du mod — même prédicat que la liste
            // (`!isGroup && hasConfigFile`) : un en-tête de pack n'a pas de
            // config à lui. `live`, car l'éditeur construit ses chemins
            // depuis le dossier physique, que la pause renomme.
            if !live.isGroup && live.hasConfigFile {
                Button {
                    vm.editingModConfig = live
                } label: {
                    Label(vm.L(L10n.Settings.configModSettings), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
                .pointingHandCursor()
            }

            // « Signaler une incompatibilité… » : ouvre le sélecteur parmi
            // les mods installés (la feuille vit dans la fiche).
            // `exclamationmark.triangle` sans `.fill` : déjà utilisé ainsi
            // dans le dépôt — un nom de symbole erroné compile sans
            // avertissement et se rend en rectangle vide.
            Button(action: onReportConflict) {
                Label(vm.L(L10n.Conflicts.reportButton), systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.bordered)
            .foregroundColor(.secondary)
            .pointingHandCursor()

            Spacer()

            // La suppression, à l'écart : icône seule, rôle destructif —
            // la confirmation vit dans la fiche, qui se referme ensuite.
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .disabled(vm.pendingDeleteFolder != nil)
            .help(vm.L(L10n.Mods.deleteMod))
            .accessibilityLabel(vm.L(L10n.Mods.deleteMod))
            .accessibilityHint(vm.L(L10n.Mods.deleteModA11yHint))
            .pointingHandCursor()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    /// Activer / Mettre en pause — glyph + libellé + couleur (P6 : jamais la
    /// couleur seule). Filet tant que la bascule est en vol : `toggleMod`
    /// met les bascules en file FIFO sans dédupliquer, le double-clic doit
    /// trouver la porte fermée.
    private var stateButton: some View {
        let busy = vm.pendingToggleFolder == mod.folderName
        return Button(action: activate) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: live.isEnabled ? "pause.circle.fill" : "play.circle.fill")
                }
                Text(vm.L(live.isEnabled ? L10n.Mods.detailPause : L10n.Mods.detailActivate))
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(busy)
        .accessibilityLabel(String(format: vm.L(L10n.Mods.toggleA11yLabel), mod.name))
    }

    /// Activer un mod signalé cassé demande une confirmation ; le mettre en
    /// pause, jamais. Mêmes portes que l'ancien interrupteur, sans son
    /// debounce : un clic de bouton est déjà discret, le filet `busy` tient
    /// le double-clic.
    private func activate() {
        guard !live.isEnabled else {
            vm.toggleMod(live)
            return
        }
        if vm.activationWarning(for: live) != nil {
            pendingActivation = live
        } else if let other = vm.conflictWarning(for: live) {
            pendingConflict = ConflictActivation(mod: live, other: other)
        } else {
            vm.toggleMod(live)
        }
    }
}
