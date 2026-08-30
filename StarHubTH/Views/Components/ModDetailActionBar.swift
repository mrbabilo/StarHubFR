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

    /// Position optimiste du toggle pendant que le dossier est renommé,
    /// `nil` dès que `vm.mods` a rattrapé — sinon l'interrupteur revient
    /// visiblement en arrière le temps du rescan.
    @State private var localIsOn: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            stateToggle

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

            // Les fichiers du mod, dans le Finder : à 900 mods, la question
            // « qu'y a-t-il donc dans ce dossier » se pose plus souvent
            // qu'on ne l'admet. Le dossier **physique** — le point de la
            // pause compris.
            Button(action: revealInFinder) {
                Label(vm.L(L10n.Mods.revealInFinder), systemImage: "folder")
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

    /// Activer / Mettre en pause — l'interrupteur vert de la rangée de
    /// liste, au token près (P6 : l'état se lit de la même teinte des deux
    /// écrans ; le bouton bleu essayé en premier se lisait moins bien).
    /// Filet tant que la bascule est en vol : `toggleMod` met les bascules
    /// en file FIFO sans dédupliquer, le double-clic doit trouver la porte
    /// fermée — le débordement du debounce que tenait l'ancienne rangée.
    private var stateToggle: some View {
        let busy = vm.pendingToggleFolder == mod.folderName
        return HStack(spacing: 8) {
            // La place du témoin est réservée en permanence : le faire
            // apparaître et disparaître décalerait le reste de la rangée.
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .opacity(busy ? 1 : 0)
            Toggle(vm.L(L10n.Mods.detailEnabled), isOn: Binding(
                get: { localIsOn ?? live.isEnabled },
                set: { newValue in
                    localIsOn = newValue
                    guard newValue != live.isEnabled else { localIsOn = nil; return }
                    // Activer un mod signalé cassé demande une confirmation ;
                    // le mettre en pause, jamais.
                    if vm.activationWarning(for: live) != nil {
                        localIsOn = nil
                        pendingActivation = live
                    } else if let other = vm.conflictWarning(for: live) {
                        localIsOn = nil
                        pendingConflict = ConflictActivation(mod: live, other: other)
                    } else {
                        vm.toggleMod(live) { localIsOn = nil }
                    }
                }
            ))
            .toggleStyle(SwitchToggleStyle(tint: AppDesign.Color.installed))
            .controlSize(.small)
            .disabled(busy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: vm.L(L10n.Mods.toggleA11yLabel), mod.name))
        .accessibilityHint(vm.L(L10n.Mods.toggleA11yHint))
    }

    /// Ouvre le dossier du mod dans le Finder — le **physique**, point de
    /// pause compris ; un composant y mène par son chemin relatif.
    private func revealInFinder() {
        let folder = URL(fileURLWithPath: (vm.gameDir as NSString).appendingPathComponent("Mods"))
            .appendingPathComponent(live.physicalFolderName)
        NSWorkspace.shared.open(folder)
    }
}
