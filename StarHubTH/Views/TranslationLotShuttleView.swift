import SwiftUI
import UniformTypeIdentifiers

/// C3-T5 — l'encart « lot pour traducteur » de la page « Traductions FR » :
/// exporter d'un coup les lots JSON de plusieurs mods dans **un** ZIP pour
/// un traducteur extérieur, et fusionner en retour un ZIP ou un JSON isolé.
///
/// Le ZIP reste un conteneur banal : chaque fichier est le lot d'un mod, au
/// format déjà déposé dans un chat — le traducteur peut le traiter mod par
/// mod, à sa main, et rendre des JSON isolés ou le ZIP entier.
struct TranslationLotShuttleView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// La session de fusion partagée avec la feuille d'arbitrage.
    @Binding var mergeStore: TranslationLotMergeStore
    /// Appelé quand une session de fusion est prête : `true` ouvre la feuille.
    let onMergeReady: (Bool) -> Void
    @State private var showingPicker = false
    @State private var building = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            shuttleRow
            footer
        }
    }

    private var shuttleRow: some View {
        HStack(spacing: AppDesign.Spacing.md) {
            Label(localization.L(L10n.FrTranslations.shuttleTitle),
                  systemImage: "shippingbox")
                .font(AppDesign.Font.caption.weight(.medium))
            Button {
                showingPicker = true
            } label: {
                Label(localization.L(L10n.FrTranslations.shuttleExport),
                      systemImage: "square.and.arrow.up")
            }
            .disabled(building)
            .help(localization.L(L10n.FrTranslations.shuttleExportHint))
            Button {
                importArchive()
            } label: {
                Label(localization.L(L10n.FrTranslations.shuttleImport),
                      systemImage: "square.and.arrow.down")
            }
            .disabled(building || mergeStore.busy)
            .help(localization.L(L10n.FrTranslations.shuttleImportHint))
            if building {
                ProgressView().controlSize(.small)
                Text(localization.L(L10n.FrTranslations.shuttleBuilding))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .sheet(isPresented: $showingPicker) {
            LotPickerSheet(viewModel: viewModel, localization: localization, onDone: { message in
                showingPicker = false
                self.message = message
            })
        }
    }

    /// Le compte rendu du dernier geste, sous l'encart — export ou import.
    @ViewBuilder
    var footer: some View {
        if let message {
            Text(message)
                .font(AppDesign.Font.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Import ZIP / JSON

    /// Lit un `.zip` ou un `.json` isolé. **La signature, pas le nom** : un
    /// fichier renommé reste ce que sont ses octets. Chaque lot est routé
    /// par son champ `mod` ; un mod absent du parc est un refus nommé, pas
    /// un blocage du fichier entier.
    private func importArchive() {
        let panel = NSOpenPanel()
        panel.title = localization.L(L10n.FrTranslations.shuttleImport)
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            message = localization.L(L10n.Mods.translationLotUnreadable)
            return
        }
        Task {
            building = true
            defer { building = false }
            let entries = collectEntries(from: data)
            guard !entries.isEmpty else {
                message = localization.L(L10n.Mods.translationLotUnreadable)
                return
            }
            var prepared: [(mod: ModItem, data: Data, rows: [TranslationCoverage.DiffRow])] = []
            var unknown: [String] = []
            for (folder, lotData) in entries {
                guard let mod = viewModel.mods.first(where: { $0.folderName == folder }) else {
                    unknown.append(folder)
                    continue
                }
                let rows = await viewModel.translationDiff(for: mod)
                prepared.append((mod, lotData, rows))
            }
            let ready = await mergeStore.prepare(entries: prepared,
                                                 unknownFolders: unknown)
            if ready {
                message = nil
                onMergeReady(true)
            } else {
                message = localization.L(L10n.Mods.translationLotMergeNothingNew)
            }
        }
    }

    /// Les lots portés par les octets reçus : un ZIP en déballé, un JSON
    /// isolé en singleton. Le dossier de mod vient du **champ `mod`** du lot,
    /// jamais du nom de fichier — un traducteur a le droit de renommer.
    private func collectEntries(from data: Data) -> [String: Data] {
        if data.starts(with: [0x50, 0x4B]) {
            let files: [String: Data]
            do {
                files = try TranslationLotArchive.extract(data)
            } catch {
                return [:]
            }
            return files
        }
        return ["": data]
    }

    // MARK: - Feuille de sélection

    /// La liste cochable des mods à mettre dans le ZIP — tout coché par
    /// défaut ; un mod sans rien à traduire est exclu au moment de
    /// construire, et le compte rendu le nomme.
    private struct LotPickerSheet: View {
        var viewModel: StarHubTHViewModel
        @ObservedObject var localization: LocalizationStore
        let onDone: (String?) -> Void

        @State private var checked: Set<String> = []
        @State private var searchText = ""
        @State private var building = false
        @State private var excluded: [String] = []

        private var mods: [ModItem] {
            viewModel.mods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        private var visible: [ModItem] {
            searchText.isEmpty ? mods : mods.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.folderName.localizedCaseInsensitiveContains(searchText)
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.L(L10n.FrTranslations.shuttlePickTitle))
                    .font(.system(size: AppDesign.Font.scaled(15), weight: .semibold))
                TextField(localization.L(L10n.Mods.diffSearch), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(localization.L(L10n.FrTranslations.shuttleCheckAll)) {
                        checked = Set(visible.map(\.folderName))
                    }
                    Button(localization.L(L10n.FrTranslations.shuttleCheckNone)) {
                        checked.subtract(visible.map(\.folderName))
                    }
                    Spacer()
                    Text(String(format: localization.L(L10n.FrTranslations.shuttleChecked),
                                Int64(checked.count), Int64(mods.count)))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                }
                List(mods) { mod in
                    Toggle(isOn: Binding(
                        get: { checked.contains(mod.folderName) },
                        set: { on in
                            if on { checked.insert(mod.folderName) }
                            else { checked.remove(mod.folderName) }
                        })) {
                        Text(mod.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                .listStyle(.inset)
                HStack {
                    if !excluded.isEmpty {
                        Text(String(format:
                                localization.L(L10n.FrTranslations.shuttleExcluded),
                                Int64(excluded.count), excluded.prefix(3).joined(separator: ", ")))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(localization.L(L10n.Mods.translationBatchCancel)) {
                        onDone(nil)
                    }
                    .keyboardShortcut(.cancelAction)
                    Button {
                        build()
                    } label: {
                        if building {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(localization.L(L10n.FrTranslations.shuttleBuild))
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(building || checked.isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 480, minHeight: 520)
            .onAppear { checked = Set(mods.map(\.folderName)) }
        }

        /// Construit le ZIP : un lot JSON par mod coché, dans l'ordre des
        /// noms. Les mods sans rien à traduire sont exclus et nommés —
        /// « rien » doit se voir comme un zéro, pas se perdre dans un
        /// fichier qui n'existe pas.
        private func build() {
            building = true
            excluded = []
            Task {
                let selected = mods.filter { checked.contains($0.folderName) }
                var files: [String: Data] = [:]
                var skipped: [String] = []
                for mod in selected {
                    let rows = await viewModel.translationDiff(for: mod)
                    guard case .data(let encoded) = viewModel.exportTranslationLot(
                        mod: mod, locale: "fr", rows: rows) else {
                        skipped.append(mod.name)
                        continue
                    }
                    files["\(mod.folderName)-fr-lot.json"] = encoded
                }
                guard !files.isEmpty else {
                    building = false
                    excluded = skipped
                    onDone(localization.L(L10n.FrTranslations.shuttleNothing))
                    return
                }
                do {
                    let zip = try TranslationLotArchive.make(files: files)
                    let panel = NSSavePanel()
                    panel.title = localization.L(L10n.FrTranslations.shuttleExport)
                    panel.allowedContentTypes = [.zip]
                    panel.nameFieldStringValue = "lots-traduction-fr.zip"
                    guard panel.runModal() == .OK, let url = panel.url else {
                        building = false
                        return
                    }
                    try zip.write(to: url)
                    viewModel.log("Lot ZIP écrit : \(files.count) mods, "
                           + "\(skipped.count) exclus (rien à traduire)", level: .info)
                    building = false
                    onDone(String(format:
                            localization.L(L10n.FrTranslations.shuttleExported),
                            Int64(files.count), Int64(skipped.count)))
                } catch {
                    building = false
                    onDone(localization.L(L10n.Mods.translationLotExportFailed))
                }
            }
        }
    }
}
