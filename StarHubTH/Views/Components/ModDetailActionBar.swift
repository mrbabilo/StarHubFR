import SwiftUI

/// Les actions de la fiche (H-T4b, hiérarchisées par I-T15) : l'interrupteur
/// et les réglages du mod au premier plan, favori et « à écarter » en icônes
/// à bascule, signaler et Finder dans « … », la suppression à l'écart. Réservée au premier
/// niveau — un composant de pack ne se pilote pas seul (règle de domaine).
///
/// Les portes d'activation (compatibilité smapi.io, conflit A5) restent
/// portées par la fiche : la barre arme `pendingActivation`/`pendingConflict`
/// par bindings, les modificateurs qui les consomment décorent le body de
/// `ModDetailView`. Le signalement et la suppression sont des closures pour
/// la même raison — feuille et confirmation y vivent.
struct ModDetailActionBar: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    /// La copie figée à l'ouverture — pour l'identité (dossier, libellés).
    let mod: ModItem
    @Binding var pendingActivation: ModItem?
    @Binding var pendingConflict: ConflictActivation?
    let onReportConflict: () -> Void
    let onDelete: () -> Void

    /// L'état relu à chaque rendu : la pause renomme le dossier physique,
    /// la copie figée ne suit pas.
    private var live: ModItem {
        vm.scanStore.mods.first { $0.folderName == mod.folderName } ?? mod
    }

    /// Position optimiste du toggle pendant que le dossier est renommé,
    /// `nil` dès que `vm.scanStore.mods` a rattrapé — sinon l'interrupteur revient
    /// visiblement en arrière le temps du rescan.
    @State private var localIsOn: Bool? = nil

    var body: some View {
        // Icônes seules si la fiche est trop étroite pour les libellés.
        AdaptiveLabels { HStack(spacing: 12) {
            stateToggle

            // I-T15 — deux gestes au premier plan : l'interrupteur et les
            // réglages du mod. Le reste descend d'un cran.
            //
            // La config du mod — même prédicat que la liste
            // (`!isGroup && hasConfigFile`) : un en-tête de pack n'a pas de
            // config à lui. `live`, car l'éditeur construit ses chemins
            // depuis le dossier physique, que la pause renomme.
            if !live.isGroup && live.hasConfigFile {
                Button {
                    vm.navigationStore.setEditingModConfig(live)
                } label: {
                    Label(localization.L(L10n.Settings.configModSettings), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .help(localization.L(L10n.Settings.configModSettings))
                .pointingHandCursor()
            }

            // Favori et « À écarter » : des marques, pas des actions — icônes
            // à bascule, l'état se lit au glyphe plein. `live` pour rester
            // d'accord avec la liste après un aller-retour.
            markToggle(isOn: vm.isFavorite(live), on: "star.fill", off: "star", tint: .yellow,
                       label: vm.isFavorite(live) ? L10n.Mods.favoriteRemove : L10n.Mods.favoriteAdd) {
                vm.toggleFavorite(live)
            }
            markToggle(isOn: vm.isBlacklisted(live), on: "xmark.circle.fill", off: "xmark.circle",
                       tint: .secondary,
                       label: vm.isBlacklisted(live) ? L10n.Mods.blacklistRemove : L10n.Mods.blacklistAdd) {
                vm.toggleBlacklist(live)
            }

            // Les gestes rares dans « … » : signaler une incompatibilité (la
            // feuille vit dans la fiche) et le dossier **physique** dans le
            // Finder, point de pause compris.
            Menu {
                Button(action: onReportConflict) {
                    Label(localization.L(L10n.Conflicts.reportButton), systemImage: "exclamationmark.triangle")
                }
                Button(action: revealInFinder) {
                    Label(localization.L(L10n.Mods.revealInFinder), systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(minWidth: 18, minHeight: 18)
            .contentShape(.rect)
            .help(localization.L(L10n.Mods.moreActions))
            .accessibilityLabel(localization.L(L10n.Mods.moreActions))
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
            .help(localization.L(L10n.Mods.deleteMod))
            .accessibilityLabel(localization.L(L10n.Mods.deleteMod))
            .accessibilityHint(localization.L(L10n.Mods.deleteModA11yHint))
            .pointingHandCursor()
        } }
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
            Toggle(localization.L(L10n.Mods.detailEnabled), isOn: Binding(
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
        .accessibilityLabel(String(format: localization.L(L10n.Mods.toggleA11yLabel), mod.name))
        .accessibilityHint(localization.L(L10n.Mods.toggleA11yHint))
    }

    /// Une marque à bascule en icône seule : cible 18×18 (sans quoi `.help`
    /// reste muet), libellé d'accessibilité et trait « sélectionné ».
    private func markToggle(isOn: Bool, on: String, off: String, tint: Color, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? on : off)
                .foregroundColor(isOn ? tint : .secondary)
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(localization.L(label))
        .accessibilityLabel(localization.L(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .pointingHandCursor()
    }

    /// Ouvre le dossier du mod dans le Finder — le **physique**, point de
    /// pause compris ; un composant y mène par son chemin relatif.
    private func revealInFinder() {
        let folder = URL(fileURLWithPath: (vm.gameDir as NSString).appendingPathComponent("Mods"))
            .appendingPathComponent(live.physicalFolderName)
        NSWorkspace.shared.open(folder)
    }
}
