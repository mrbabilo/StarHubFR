import SwiftUI

/// Les fichiers qu'une mise à jour de mod a emportés, et qu'une sauvegarde peut
/// rendre — sans restaurer le mod entier.
///
/// Une mise à jour écrase le dossier du mod : elle emporte ce que l'auteur ne
/// redistribue pas, la traduction française installée à la main en premier.
/// Mesuré sur le parc de référence le 2026-08-24 : **10 `i18n/fr.json`** ne
/// vivent plus que dans une sauvegarde.
struct RecoverableFilesView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @Binding var isPresented: Bool

    /// Le fichier dont l'aperçu est déplié. Un seul à la fois : la lecture se
    /// fait à l'ouverture, et il n'y a pas de raison d'en tenir dix en mémoire.
    @State private var previewing: RecoverableFile?
    @State private var previewText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.L(L10n.Recovery.title))
                    .font(.system(size: 16, weight: .semibold))
                Text(vm.L(L10n.Recovery.note))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Divider()

            if vm.isScanningRecoverableFiles {
                centered { ProgressView() }
            } else if vm.recoverableFiles.isEmpty {
                centered {
                    Text(vm.L(L10n.Recovery.empty))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.recoverableFiles) { file in
                            row(file)
                            if previewing?.id == file.id { preview }
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(vm.L(L10n.ModInstall.refreshBackups)) { vm.scanRecoverableFiles() }
                    .disabled(vm.isScanningRecoverableFiles)
                Spacer()
                Button(vm.L(L10n.Main.ok)) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 500)
        .onAppear { if vm.recoverableFiles.isEmpty { vm.scanRecoverableFiles() } }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity)
    }

    private func row(_ file: RecoverableFile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.modName)
                    .font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(file.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                    Text(reasonLabel(file.reason))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // L'aperçu avant l'écriture : on n'écrase pas un fichier du dossier
            // d'un mod sans avoir montré ce qu'on y met.
            Button(vm.L(L10n.Recovery.preview)) { togglePreview(file) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointingHandCursor()
            Button(vm.L(L10n.Recovery.recover)) { vm.recoverFile(file) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var preview: some View {
        ScrollView {
            Text(previewText)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func togglePreview(_ file: RecoverableFile) {
        if previewing?.id == file.id {
            previewing = nil
            previewText = ""
            return
        }
        previewing = file
        // Tronqué : un `fr.json` de mod dépasse les vingt mille caractères, et
        // l'aperçu sert à reconnaître le fichier, pas à le relire en entier.
        let raw = (try? String(contentsOfFile: file.backupPath, encoding: .utf8)) ?? ""
        previewText = raw.count > 4000 ? String(raw.prefix(4000)) + "\n…" : raw
    }

    private func reasonLabel(_ reason: RecoveryReason) -> String {
        switch reason {
        case .absentFromInstall:
            return vm.L(L10n.Recovery.reasonAbsent)
        case .keysLostSinceBackup(let keys):
            return String(format: vm.L(L10n.Recovery.reasonLostKeys), Int64(keys.count))
        }
    }
}
