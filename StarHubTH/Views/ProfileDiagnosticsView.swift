import SwiftUI

/// Ce qui empêchera ce profil de tourner tel quel : les mods qu'il réclame et
/// qui ne sont plus installés, et les dépendances requises qu'il laisse de côté.
///
/// Sans cet écran, un profil qui a perdu des mods s'applique en silence : le
/// jeu démarre amputé, et rien ne dit lesquels manquent. C'est d'autant plus
/// sensible que ces mods sont souvent des **cadres** dont d'autres dépendent
/// (SpaceCore, Json Assets, GMCM) — leur absence casse plus que leur propre
/// fonctionnalité.
///
/// Et, depuis B3-T4, ce que le profil affichera **en français** : là, rien
/// n'est cassé — une clé sans traduction s'affiche en anglais —, mais deux
/// profils n'ont ni la même liste de mods ni la même part de français, et rien
/// ne le disait. Cette troisième section a sa propre porte d'entrée (la
/// pastille « FR » de la ligne du profil), sans quoi elle resterait invisible
/// sur un profil sans le moindre défaut.
///
/// R4 : et les `config.json` qu'il retient, avec la comparaison entre
/// profils — la feuille devient la fiche du profil. Chaque porte de la rangée
/// (Anomalies, pastille FR, colonnes Configs et Mods) l'ouvre sur sa section.
/// P5-1 : la colonne Mods mène à ce qu'activer le profil ferait.
struct ProfileDiagnosticsView: View {
    /// La section sur laquelle la feuille s'ouvre ; `nil` = en haut.
    enum Focus: Hashable { case preview, translation, configs }

    /// Le profil **et** sa section, dans l'item de `.sheet(item:)` : un
    /// `@State` lu seulement dans la closure de la feuille y arrivait périmé.
    struct Request: Identifiable {
        let profile: ModProfile
        let focus: Focus?
        var id: UUID { profile.id }
    }

    private struct Comparison: Equatable {
        let mod: ModItem
        let other: ModProfile
    }

    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let profile: ModProfile
    @Binding var isPresented: Bool
    /// Ouvre la fiche d'un mod sur son onglet Traduction. Confié à l'appelant :
    /// c'est lui qui tient l'onglet courant de la fenêtre.
    let onOpenTranslation: (String) -> Void
    var focus: Focus?

    /// Calculé une fois à l'ouverture : la résolution lit l'index des
    /// sauvegardes sur le disque, ce qu'on ne refait pas à chaque rendu.
    @State private var missing: [MissingProfileMod] = []
    @State private var gaps: [ProfileDependencyGap] = []
    /// La couverture française du profil (B3-T4). Mesurée par le ViewModel à
    /// l'ouverture de la page des profils : cette feuille la lit, elle ne la
    /// calcule pas.
    @State private var translation: ProfileTranslationSummary?
    @State private var configs = ProfileConfigOverview(storedFolders: [], installed: [])
    /// P5-1 — ce qu'activer le profil ferait, sur les mods de tête (le plan).
    @State private var preview: ProfileApplyPreview?
    /// La comparaison affichée **par-dessus** la liste, qui reste montée :
    /// au retour, le défilement est là où on l'avait laissé.
    @State private var comparison: Comparison?
    /// Nombre de `reload()` faits : le défilement vers `focus` attend le premier.
    @State private var loads = 0

    var body: some View {
        ZStack {
            content
                .opacity(comparison == nil ? 1 : 0)
                .allowsHitTesting(comparison == nil)
                // Désactivé, son OK ne capte plus ↩ : le « ‹ Retour » de la
                // comparaison est alors le seul `.defaultAction` de la feuille.
                .disabled(comparison != nil)
                .accessibilityHidden(comparison != nil)
            if let comparison {
                ProfileConfigCompareView(vm: viewModel, localization: localization, mod: comparison.mod,
                                         other: comparison.other,
                                         isPresented: Binding(get: { true }, set: { if !$0 { self.comparison = nil } }),
                                         embedded: true)
                    .background(AppDesign.Color.windowBg)
            }
        }
        .frame(width: 640, height: 500)
        .onAppear { reload() }
        // La restauration relance un scan **asynchrone** : recalculer juste
        // après l'avoir lancée lit encore l'ancien `viewModel.scanStore.mods`, et le mod
        // restauré resterait affiché comme manquant. On refait le calcul quand
        // le parc a réellement changé.
        .onChange(of: viewModel.scanStore.mods.count) { _, _ in reload() }
        // Ajouter une dépendance au profil change le profil, pas le parc : le
        // compte de mods est le signal qui l'annonce.
        .onChange(of: viewModel.modProfiles) { _, _ in reload() }
        // La mesure de la couverture tourne en fond : sans ceci, une feuille
        // ouverte pendant la passe resterait sur son témoin d'attente.
        .onChange(of: viewModel.profileTranslationSummaries) { _, _ in reload() }
        // Une bascule ne change pas le compte : l'aperçu se refait à la fin du scan.
        .onChange(of: viewModel.scanStore.scanProgress == nil) { _, _ in reload() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: localization.L(L10n.Profiles.diagnosticTitle), profile.name))
                    .font(AppDesign.Font.headline(.semibold))
                // Seulement quand des mods manquent vraiment : cette feuille
                // s'ouvre aussi depuis la couverture française d'un profil
                // sans le moindre défaut, et l'accueillir par « ce profil
                // réclame des mods qui ne sont plus installés » serait faux.
                if !missing.isEmpty {
                    Text(localization.L(L10n.Profiles.missingNote) + " " + localization.L(L10n.Profiles.missingRestoreNote))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Divider()

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !missing.isEmpty {
                        sectionHeader(localization.L(L10n.Profiles.sectionMissing))
                        ForEach(missing) { mod in
                            row(mod)
                            Divider().padding(.leading, 20)
                        }
                    }
                    if !gaps.isEmpty {
                        sectionHeader(localization.L(L10n.Profiles.sectionDependencies))
                        ForEach(gaps) { gap in
                            gapRow(gap)
                            Divider().padding(.leading, 20)
                        }
                    }
                    if let preview {
                        sectionHeader(localization.L(L10n.ProfilePreview.section))
                            .id(Focus.preview)
                        ProfilePreviewSection(localization: localization, preview: preview,
                                              isScanning: viewModel.scanStore.scanProgress != nil)
                    }
                    translationSection
                    if configs.total > 0 {
                        sectionHeader(localization.L(L10n.Profiles.sectionConfigs))
                            .id(Focus.configs)
                        ProfileConfigsSection(viewModel: viewModel, localization: localization, profile: profile,
                                              overview: configs) { mod, other in
                            comparison = Comparison(mod: mod, other: other)
                        }
                    }
                }
            }
            // Après le premier `reload()`, que la feuille fait à son apparition :
            // ni `onAppear` (la section n'existait pas encore) ni `onChange`
            // (posé après le premier chargement, il ne voyait aucun changement).
            .task(id: loads) {
                guard loads == 1, let focus else { return }
                await Task.yield()
                proxy.scrollTo(focus, anchor: .top)
            }
            }

            Divider()

            HStack {
                Spacer()
                Button(localization.L(L10n.Main.ok)) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private func reload() {
        // Le profil est relu depuis le ViewModel : celui que la feuille porte
        // est une copie prise à l'ouverture, et ne verrait pas les dépendances
        // qu'on vient d'y ajouter.
        let current = viewModel.modProfiles.first { $0.id == profile.id } ?? profile
        missing = viewModel.missingMods(in: current)
        gaps = ProfileDiagnostics.dependencyGaps(in: current, installedMods: viewModel.scanStore.mods.flattenedMods)
        translation = viewModel.translationSummary(for: current)
        configs = ProfileConfigOverview.load(profileId: current.id, installed: viewModel.scanStore.mods.flattenedMods)
        preview = ProfileApplyPreview.make(applying: current, to: viewModel.mods,
                                           verdicts: viewModel.modConflictVerdicts,
                                           candidates: viewModel.conflictCandidates)
        loads += 1
    }

    /// Ce que le profil affichera en français une fois appliqué.
    ///
    /// Rangée à part des deux autres sections, et sous elles : ce n'est pas un
    /// défaut. Une clé sans traduction s'affiche en anglais et le jeu tourne —
    /// la note le dit, faute de quoi l'écran crierait au problème là où il n'y
    /// en a pas.
    @ViewBuilder
    private var translationSection: some View {
        if translation == nil, viewModel.isMeasuringProfileTranslation {
            // La feuille peut s'ouvrir par la pastille d'anomalies avant que la
            // mesure ne soit finie : le dire vaut mieux qu'une section absente,
            // qu'on prendrait pour « rien à traduire ».
            sectionHeader(localization.L(L10n.Profiles.sectionTranslation))
                .id(Focus.translation)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(localization.L(L10n.Profiles.translationMeasuring))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        } else if let summary = translation, !summary.isEmpty {
            sectionHeader(localization.L(L10n.Profiles.sectionTranslation))
                .id(Focus.translation)
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: localization.L(L10n.Profiles.translationSummary),
                            Int64(summary.translatedKeys), Int64(summary.totalKeys),
                            summary.displayPercent,
                            Int64(summary.translatableCount),
                            Int64(summary.fullyTranslatedCount)))
                    .font(AppDesign.Font.caption)
                Text(localization.L(L10n.Profiles.translationNote))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if summary.pending.isEmpty {
                Text(localization.L(L10n.Profiles.translationAllDone))
                    .font(AppDesign.Font.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            } else {
                Divider().padding(.leading, 20)
                ForEach(summary.pending) { mod in
                    translationRow(mod)
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    /// Un mod qu'il reste à traduire. Le geste ouvre son onglet Traduction —
    /// sans lui, la section ne ferait que constater.
    private func translationRow(_ mod: ProfileModTranslation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name)
                    .font(AppDesign.Font.body)
                Text(String(format: localization.L(L10n.Profiles.translationRowCounts),
                            Int64(mod.translated), Int64(mod.total),
                            Int64(mod.missingCount)))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Le pourcentage à chasse fixe, comme la pastille de la liste des
            // mods : deux rangées voisines ne doivent pas décaler leur nombre.
            Text("\(mod.displayPercent) %")
                .font(.system(size: AppDesign.Font.scaled(11), weight: .medium, design: .monospaced))
                .foregroundColor(mod.translated == 0 ? .secondary : AppDesign.Color.accent)

            Button(localization.L(L10n.Profiles.translationOpen)) {
                // Ouvre la fiche du mod sur son onglet Traduction. Passer par
                // `.jumpToMod` n'aurait fait que **cadrer la liste** — la fiche
                // s'ouvre par `viewingModDetail` — et aurait laissé la liste
                // filtrée sur ce mod au retour.
                onOpenTranslation(mod.folderName)
                isPresented = false
            }
            .buttonStyle(.bordered).focusRing(cornerRadius: 5)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(AppDesign.Font.footnote(.semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Une dépendance requise que le profil ne retient pas. Deux cas, deux
    /// gestes : l'ajouter au profil quand elle est installée, la télécharger
    /// quand elle ne l'est pas — et là, on ne sait pas encore où.
    private func gapRow(_ gap: ProfileDependencyGap) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gap.displayName)
                    .font(AppDesign.Font.body)
                Text(String(format: localization.L(L10n.Profiles.requiredByCount),
                            Int64(gap.requiredBy.count),
                            gap.requiredBy.prefix(3).joined(separator: ", ")))
                    .font(AppDesign.Font.iconXS)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if gap.isInstalled {
                // Ajouter une dépendance à un profil **actif** déplace un
                // dossier et relance un scan : le voile de progression vit dans
                // la fenêtre, donc derrière cette feuille. Sans ce témoin, le
                // clic n'aurait aucun effet visible pendant plusieurs secondes.
                if viewModel.isApplyingProfile {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(localization.L(L10n.Profiles.addToProfile)) {
                        viewModel.addModToProfile(id: profile.id, uniqueId: gap.uniqueId)
                    }
                    .buttonStyle(.bordered).focusRing(cornerRadius: 5)
                    .controlSize(.small)
                    .pointingHandCursor()
                }
            } else {
                // Gravité = glyph **et** couleur (P6) : l'orange seul ne dit
                // pas « manque », surtout à côté d'un libellé neutre.
                HStack(spacing: AppDesign.Spacing.xs) {
                    Image(systemName: AppDesign.Status.warning.symbol)
                        .font(AppDesign.Font.iconXS)
                    Text(localization.L(L10n.Profiles.dependencyNotInstalled))
                        .font(AppDesign.Font.footnote)
                }
                .foregroundColor(AppDesign.Color.warning)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func row(_ mod: MissingProfileMod) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.displayName)
                    .font(AppDesign.Font.body)
                // L'identifiant reste visible : c'est ce que l'utilisateur
                // retrouvera dans un manifeste ou dans un journal SMAPI, et
                // pour les profils d'avant c'est parfois tout ce qu'on a.
                Text(mod.uniqueId)
                    .font(AppDesign.Font.monoIconXS)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if mod.isBundledWithSmapi {
                // Proposer Nexus ici serait un mauvais conseil : ce mod revient
                // avec une réinstallation de SMAPI, et n'a pas de page à lui.
                Text(localization.L(L10n.Profiles.missingBundled))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
            } else {
                if mod.hasBackup {
                    Button(localization.L(L10n.Profiles.missingRestore)) {
                        viewModel.restoreMissingModFromBackup(uniqueId: mod.uniqueId)
                    }
                    .buttonStyle(.bordered).focusRing(cornerRadius: 5)
                    .controlSize(.small)
                    .pointingHandCursor()
                }
                if let nexusId = mod.nexusModId, let id = Int(nexusId) {
                    Button(localization.L(L10n.ModInstall.depDownload)) {
                        viewModel.downloadModFromNexus(nexusId: id)
                    }
                    .buttonStyle(.bordered).focusRing(cornerRadius: 5)
                    .controlSize(.small)
                    // L'API refuse tout lien direct à un compte non premium :
                    // proposer le bouton reviendrait à promettre un échec.
                    .disabled(viewModel.isDownloadingFromNexus || viewModel.nexusDirectDownloadUnavailable)
                    .help(viewModel.nexusDirectDownloadUnavailable ? localization.L(L10n.Mods.premiumOnlyHint) : "")
                    .pointingHandCursor()
                } else if !mod.hasBackup {
                    Text(localization.L(L10n.Profiles.missingUnknown))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
