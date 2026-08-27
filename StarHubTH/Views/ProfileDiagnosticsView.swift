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
struct ProfileDiagnosticsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let profile: ModProfile
    @Binding var isPresented: Bool
    /// Ouvre la fiche d'un mod sur son onglet Traduction. Confié à l'appelant :
    /// c'est lui qui tient l'onglet courant de la fenêtre.
    let onOpenTranslation: (String) -> Void

    /// Calculé une fois à l'ouverture : la résolution lit l'index des
    /// sauvegardes sur le disque, ce qu'on ne refait pas à chaque rendu.
    @State private var missing: [MissingProfileMod] = []
    @State private var gaps: [ProfileDependencyGap] = []
    /// La couverture française du profil (B3-T4). Mesurée par le ViewModel à
    /// l'ouverture de la page des profils : cette feuille la lit, elle ne la
    /// calcule pas.
    @State private var translation: ProfileTranslationSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: vm.L(L10n.Profiles.diagnosticTitle), profile.name))
                    .font(.system(size: 16, weight: .semibold))
                // Seulement quand des mods manquent vraiment : cette feuille
                // s'ouvre aussi depuis la couverture française d'un profil
                // sans le moindre défaut, et l'accueillir par « ce profil
                // réclame des mods qui ne sont plus installés » serait faux.
                if !missing.isEmpty {
                    Text(vm.L(L10n.Profiles.missingNote) + " " + vm.L(L10n.Profiles.missingRestoreNote))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !missing.isEmpty {
                        sectionHeader(vm.L(L10n.Profiles.sectionMissing))
                        ForEach(missing) { mod in
                            row(mod)
                            Divider().padding(.leading, 20)
                        }
                    }
                    if !gaps.isEmpty {
                        sectionHeader(vm.L(L10n.Profiles.sectionDependencies))
                        ForEach(gaps) { gap in
                            gapRow(gap)
                            Divider().padding(.leading, 20)
                        }
                    }
                    translationSection
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
        .frame(width: 560, height: 460)
        .onAppear { reload() }
        // La restauration relance un scan **asynchrone** : recalculer juste
        // après l'avoir lancée lit encore l'ancien `vm.mods`, et le mod
        // restauré resterait affiché comme manquant. On refait le calcul quand
        // le parc a réellement changé.
        .onChange(of: vm.mods.count) { _, _ in reload() }
        // Ajouter une dépendance au profil change le profil, pas le parc : le
        // compte de mods est le signal qui l'annonce.
        .onChange(of: vm.modProfiles) { _, _ in reload() }
        // La mesure de la couverture tourne en fond : sans ceci, une feuille
        // ouverte pendant la passe resterait sur son témoin d'attente.
        .onChange(of: vm.profileTranslationSummaries) { _, _ in reload() }
    }

    private func reload() {
        // Le profil est relu depuis le ViewModel : celui que la feuille porte
        // est une copie prise à l'ouverture, et ne verrait pas les dépendances
        // qu'on vient d'y ajouter.
        let current = vm.modProfiles.first { $0.id == profile.id } ?? profile
        missing = vm.missingMods(in: current)
        gaps = ProfileDiagnostics.dependencyGaps(in: current, installedMods: vm.mods.flattenedMods)
        translation = vm.translationSummary(for: current)
    }

    /// Ce que le profil affichera en français une fois appliqué.
    ///
    /// Rangée à part des deux autres sections, et sous elles : ce n'est pas un
    /// défaut. Une clé sans traduction s'affiche en anglais et le jeu tourne —
    /// la note le dit, faute de quoi l'écran crierait au problème là où il n'y
    /// en a pas.
    @ViewBuilder
    private var translationSection: some View {
        if translation == nil, vm.isMeasuringProfileTranslation {
            // La feuille peut s'ouvrir par la pastille d'anomalies avant que la
            // mesure ne soit finie : le dire vaut mieux qu'une section absente,
            // qu'on prendrait pour « rien à traduire ».
            sectionHeader(vm.L(L10n.Profiles.sectionTranslation))
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(vm.L(L10n.Profiles.translationMeasuring))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        } else if let summary = translation, !summary.isEmpty {
            sectionHeader(vm.L(L10n.Profiles.sectionTranslation))
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: vm.L(L10n.Profiles.translationSummary),
                            Int64(summary.translatedKeys), Int64(summary.totalKeys),
                            summary.displayPercent,
                            Int64(summary.translatableCount),
                            Int64(summary.fullyTranslatedCount)))
                    .font(.system(size: 12))
                Text(vm.L(L10n.Profiles.translationNote))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if summary.pending.isEmpty {
                Text(vm.L(L10n.Profiles.translationAllDone))
                    .font(.system(size: 12))
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
                    .font(.system(size: 13))
                Text(String(format: vm.L(L10n.Profiles.translationRowCounts),
                            Int64(mod.translated), Int64(mod.total),
                            Int64(mod.missingCount)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Le pourcentage à chasse fixe, comme la pastille de la liste des
            // mods : deux rangées voisines ne doivent pas décaler leur nombre.
            Text("\(mod.displayPercent) %")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(mod.translated == 0 ? .secondary : .accentColor)

            Button(vm.L(L10n.Profiles.translationOpen)) {
                // Ouvre la fiche du mod sur son onglet Traduction. Passer par
                // `.jumpToMod` n'aurait fait que **cadrer la liste** — la fiche
                // s'ouvre par `viewingModDetail` — et aurait laissé la liste
                // filtrée sur ce mod au retour.
                onOpenTranslation(mod.folderName)
                isPresented = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 13))
                Text(String(format: vm.L(L10n.Profiles.requiredByCount),
                            Int64(gap.requiredBy.count),
                            gap.requiredBy.prefix(3).joined(separator: ", ")))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if gap.isInstalled {
                // Ajouter une dépendance à un profil **actif** déplace un
                // dossier et relance un scan : le voile de progression vit dans
                // la fenêtre, donc derrière cette feuille. Sans ce témoin, le
                // clic n'aurait aucun effet visible pendant plusieurs secondes.
                if vm.isApplyingProfile {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(vm.L(L10n.Profiles.addToProfile)) {
                        vm.addModToProfile(id: profile.id, uniqueId: gap.uniqueId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
                }
            } else {
                Text(vm.L(L10n.Profiles.dependencyNotInstalled))
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func row(_ mod: MissingProfileMod) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.displayName)
                    .font(.system(size: 13))
                // L'identifiant reste visible : c'est ce que l'utilisateur
                // retrouvera dans un manifeste ou dans un journal SMAPI, et
                // pour les profils d'avant c'est parfois tout ce qu'on a.
                Text(mod.uniqueId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if mod.isBundledWithSmapi {
                // Proposer Nexus ici serait un mauvais conseil : ce mod revient
                // avec une réinstallation de SMAPI, et n'a pas de page à lui.
                Text(vm.L(L10n.Profiles.missingBundled))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if mod.hasBackup {
                    Button(vm.L(L10n.Profiles.missingRestore)) {
                        vm.restoreMissingModFromBackup(uniqueId: mod.uniqueId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
                }
                if let nexusId = mod.nexusModId, let id = Int(nexusId) {
                    Button(vm.L(L10n.ModInstall.depDownload)) {
                        vm.downloadModFromNexus(nexusId: id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    // L'API refuse tout lien direct à un compte non premium :
                    // proposer le bouton reviendrait à promettre un échec.
                    .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable)
                    .help(vm.nexusDirectDownloadUnavailable ? vm.L(L10n.Mods.premiumOnlyHint) : "")
                    .pointingHandCursor()
                } else if !mod.hasBackup {
                    Text(vm.L(L10n.Profiles.missingUnknown))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
