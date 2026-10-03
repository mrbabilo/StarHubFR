import SwiftUI

/// Dans l'aperçu d'une mise à jour : la mise à jour apporte son `fr.json`
/// alors qu'une traduction locale existe — la comparaison, puis le choix
/// (garder, prendre celle de l'auteur, fusionner). Muet quand les deux
/// sont identiques ou qu'un seul côté existe. Règles : `TranslationUpdate`
/// (Core, testé).
struct InstallTranslationChoice: View {
    let mod: DetectedMod
    let existing: ModItem
    let tempDir: URL?
    let gameDir: String
    let selection: InstallSelection?
    let onChange: (InstallSelection) -> Void
    @ObservedObject var localization: LocalizationStore
    /// Lu une fois à l'apparition : quelques fichiers, jamais dans `body`.
    @State private var comparison: TranslationUpdate.Comparison?

    var body: some View {
        Group {
            if let comparison {
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(format: localization.L(L10n.ModInstall.translationUpdateSummary),
                                 comparison.authorKeys, comparison.differing,
                                 comparison.authorOnly, comparison.localOnly),
                          systemImage: "character.bubble")
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(AppDesign.Color.info)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker("", selection: choice) {
                        Text(localization.L(L10n.ModInstall.translationKeepLocal)).tag(TranslationUpdate.Choice.keepLocal)
                        Text(localization.L(L10n.ModInstall.translationTakeAuthor)).tag(TranslationUpdate.Choice.takeAuthor)
                        Text(localization.L(L10n.ModInstall.translationMerge)).tag(TranslationUpdate.Choice.merge)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }
        }
        .task(id: mod.id) { comparison = compare() }
    }

    private var choice: Binding<TranslationUpdate.Choice> {
        Binding(get: { selection?.translationChoice ?? .keepLocal },
                set: { value in
                    onChange((selection ?? InstallSelection(modId: mod.id, selected: true,
                                                            conflictResolution: nil)).with(translation: value))
                })
    }

    /// Tous les `fr.json` du mod (composants compris) réunis en un bilan.
    private func compare() -> TranslationUpdate.Comparison? {
        guard let tempDir, !gameDir.isEmpty else { return nil }
        let source = mod.relativePath.isEmpty ? tempDir : tempDir.appendingPathComponent(mod.relativePath)
        let modsRoot = URL(fileURLWithPath: gameDir).appendingPathComponent("Mods")
        guard let installed = ModFolderPaths.realFolder(modsRoot: modsRoot, logical: existing.folderName) else { return nil }
        let all = TranslationUpdate.comparisons(source: source, installed: installed).values
        guard !all.isEmpty else { return nil }
        return all.reduce(TranslationUpdate.Comparison(localKeys: 0, authorKeys: 0, differing: 0,
                                                       authorOnly: 0, localOnly: 0)) {
            TranslationUpdate.Comparison(localKeys: $0.localKeys + $1.localKeys, authorKeys: $0.authorKeys + $1.authorKeys,
                                         differing: $0.differing + $1.differing, authorOnly: $0.authorOnly + $1.authorOnly,
                                         localOnly: $0.localOnly + $1.localOnly)
        }
    }
}
