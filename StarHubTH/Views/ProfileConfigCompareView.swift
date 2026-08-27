import SwiftUI

/// Ce que deux profils retiennent du `config.json` d'un mod, clé à clé —
/// l'écran qui rend la divergence *lisible* (spec §7).
///
/// **Lecture seule**, délibérément : un bouton « copier cette valeur de A
/// vers B » ouvrirait un second chemin d'écriture dans les configs ; la spec
/// exige le premier éprouvé avant d'instruire le second. Le patron vient de
/// `TranslationRecoveryDiffView` ; le code n'est pas repris — la
/// comparaison de traduction travaille sur des fichiers plats, celle-ci
/// sur des arbres à 8 niveaux.
struct ProfileConfigCompareView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem
    let other: ModProfile
    @Binding var isPresented: Bool

    /// Rempli à l'apparition, jamais au rendu : chaque appel ouvre et
    /// décode les magasins des deux profils.
    @State private var diffs: [ConfigKeyDiff] = []
    @State private var unparseable = false
    @State private var missing = false

    private var activeName: String {
        vm.modProfiles.first(where: { $0.id == vm.activeProfileId })?.name ?? ""
    }

    private var onlyA: [ConfigKeyDiff] { diffs.filter { $0.kind == .onlyInA } }
    private var differs: [ConfigKeyDiff] { diffs.filter { $0.kind == .valueDiffers } }
    private var onlyB: [ConfigKeyDiff] { diffs.filter { $0.kind == .onlyInB } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: vm.L(L10n.Mods.profileConfigDiffTitle),
                            mod.name, activeName, other.name))
                    .font(.system(size: 16, weight: .semibold))
                Text(vm.L(L10n.Mods.profileConfigDiffNote))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            if missing {
                centered(vm.L(L10n.Mods.profileConfigDiffMissing))
            } else if unparseable {
                centered(vm.L(L10n.Mods.profileConfigDiffUnparseable))
            } else if diffs.isEmpty {
                centered(vm.L(L10n.Mods.profileConfigDiffNone))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        section(String(format: vm.L(L10n.Mods.profileConfigDiffOnlyA),
                                       activeName), items: onlyA)
                        section(vm.L(L10n.Mods.profileConfigDiffDiffers), items: differs)
                        section(String(format: vm.L(L10n.Mods.profileConfigDiffOnlyB),
                                       other.name), items: onlyB)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button(vm.L(L10n.Main.ok)) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 540)
        .onAppear {
            // Rien mémorisé d'un côté : ce n'est ni une erreur ni un diff —
            // l'écran le dit, il ne l'invente pas.
            guard let active = vm.modProfiles.first(where: { $0.id == vm.activeProfileId }),
                  vm.profileConfigText(mod: mod, profile: active) != nil,
                  vm.profileConfigText(mod: mod, profile: other) != nil else {
                missing = true
                return
            }
            if let result = vm.profileConfigDiffs(mod: mod, other: other) {
                diffs = result
            } else {
                unparseable = true
            }
        }
    }

    private func centered(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Une famille : en-tête + lignes. La sous-liste vient en paramètre —
    /// trier les diffs par libellé localisé serait trier des données par
    /// habillage. Une famille vide ne montre pas son en-tête : un titre
    /// seul sous lequel rien ne vient se lit comme un écran cassé.
    private func section(_ title: String, items: [ConfigKeyDiff]) -> some View {
        Group {
            if !items.isEmpty {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
                ForEach(items) { diff in
                    if diff.kind == .valueDiffers {
                        comparisonRow(diff)
                    } else {
                        row(diff)
                    }
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    /// Une valeur d'un seul côté : le chemin en monospace, la valeur
    /// dessous, sélectionnable — copier à la main reste possible même en
    /// lecture seule.
    private func row(_ diff: ConfigKeyDiff) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(diff.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Text((diff.valueA ?? diff.valueB) ?? "")
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Les deux valeurs côte à côte, étiquetées par profil — c'est ce qui
    /// permet de juger laquelle vient d'où.
    private func comparisonRow(_ diff: ConfigKeyDiff) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diff.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 12) {
                labelled(activeName, diff.valueA ?? "", color: .primary)
                labelled(other.name, diff.valueB ?? "", color: .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func labelled(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(color)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
