import SwiftUI

/// Le détail clé à clé entre la traduction d'une sauvegarde et celle du mod
/// installé, et la récupération de ce qui manque.
///
/// Remplacer le fichier entier coûterait au traducteur ce qu'il a écrit depuis
/// la mise à jour ; ne rien faire lui coûte ce qu'il avait écrit avant. La
/// seule réponse juste est clé par clé, et **seulement** sur celles que le
/// fichier installé n'a plus : ce qui a été traduit depuis est montré, jamais
/// proposé au remplacement.
struct TranslationRecoveryDiffView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let file: RecoverableFile
    @Binding var isPresented: Bool

    @State private var diffs: [TranslationKeyDiff] = []
    @State private var selected: Set<String> = []

    private var recoverable: [TranslationKeyDiff] { diffs.filter { $0.kind == .onlyInBackup } }
    private var diverging: [TranslationKeyDiff] { diffs.filter { $0.kind == .valueDiffers } }
    private var extra: [TranslationKeyDiff] { diffs.filter { $0.kind == .onlyInInstalled } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: vm.L(L10n.Recovery.diffTitle), file.modName, file.relativePath))
                    .font(.system(size: 16, weight: .semibold))
                Text(vm.L(L10n.Recovery.note))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            if diffs.isEmpty {
                VStack {
                    Spacer()
                    Text(vm.L(L10n.Recovery.diffNothing))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !recoverable.isEmpty {
                            header(vm.L(L10n.Recovery.diffOnlyInBackup), trailing: selectAllButton)
                            ForEach(recoverable) { diff in
                                selectableRow(diff)
                                Divider().padding(.leading, 20)
                            }
                        }
                        if !diverging.isEmpty {
                            header(vm.L(L10n.Recovery.diffValueDiffers))
                            ForEach(diverging) { diff in
                                comparisonRow(diff)
                                Divider().padding(.leading, 20)
                            }
                        }
                        if !extra.isEmpty {
                            header(vm.L(L10n.Recovery.diffOnlyInInstalled))
                            ForEach(extra) { diff in
                                readOnlyRow(key: diff.key, value: diff.installedValue ?? "")
                                Divider().padding(.leading, 20)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(String(format: vm.L(L10n.Recovery.recoverKeys), Int64(selected.count))) {
                    vm.recoverTranslationKeys(recoverable.filter { selected.contains($0.key) },
                                              in: file)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                Spacer()
                Button(vm.L(L10n.Main.ok)) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 540)
        .onAppear {
            diffs = vm.translationDiff(for: file)
            // Tout coché d'entrée : ces clés sont, par construction, celles
            // qu'on ne peut pas écraser — l'utilisateur décoche ce dont il ne
            // veut pas, plutôt que de cocher trois cents lignes.
            selected = Set(recoverable.map(\.key))
        }
    }

    private var selectAllButton: some View {
        Button(vm.L(L10n.Recovery.selectAll)) {
            selected = selected.count == recoverable.count ? [] : Set(recoverable.map(\.key))
        }
        .buttonStyle(.link)
        .font(.system(size: 11))
    }

    private func header(_ title: String) -> some View {
        header(title, trailing: EmptyView())
    }

    private func header<Trailing: View>(_ title: String, trailing: Trailing) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func selectableRow(_ diff: TranslationKeyDiff) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected.contains(diff.key) },
                set: { isOn in
                    if isOn { selected.insert(diff.key) } else { selected.remove(diff.key) }
                }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(diff.key)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(diff.backupValue ?? "")
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Les deux valeurs côte à côte : c'est ce qui permet de juger que la
    /// version installée est bien la plus récente.
    private func comparisonRow(_ diff: TranslationKeyDiff) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diff.key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 12) {
                labelled(vm.L(L10n.Recovery.inBackup), diff.backupValue ?? "", color: .secondary)
                labelled(vm.L(L10n.Recovery.installed), diff.installedValue ?? "", color: .primary)
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

    private func readOnlyRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
