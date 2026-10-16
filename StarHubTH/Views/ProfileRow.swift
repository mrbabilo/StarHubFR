import SwiftUI

/// La rangée d'un profil. Sortie de `ModProfilesView` (plafond de taille,
/// audit UX 2026-10-16, I-T26) pour les lots qui la touchent.
struct ProfileRow: View {
    let profile: ModProfile
    let isActive: Bool
    let modCount: Int
    /// Ce qui empêchera le profil de tourner tel quel : mods disparus et
    /// dépendances requises laissées de côté. `0` la plupart du temps.
    let issueCount: Int
    /// La part de français du profil (B3-T4). `nil` tant que la mesure n'a pas
    /// eu lieu — elle lit le disque et n'a lieu qu'à l'ouverture de cette page.
    let translation: ProfileTranslationSummary?
    /// La mesure est en cours : un témoin, plutôt qu'un chiffre qui monterait
    /// sous les yeux de l'utilisateur.
    let isMeasuringTranslation: Bool
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let onApply: () -> Void
    let onManage: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onImportFavorites: () -> Void
    let onImportBlacklisted: () -> Void
    let onShowMissing: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    /// Ce que ce profil retient des `config.json`, rempli à l'apparition et
    /// jamais recalculé au rendu : la mesure ouvre et décode un fichier.
    @State private var configSummary: (total: Int, orphans: [String]) = (0, [])

    var body: some View {
        // A plain row (NOT a tappable button) so switching profiles — which
        // moves mod folders on disk — only ever happens via the explicit
        // "Activate"/"Manage" buttons, never an accidental click on the row.
        HStack(spacing: 14) {
            InitialsAvatar(
                text: profile.name,
                size: 40,
                fillColor: isActive ? Color.accentColor : Color.gray.opacity(0.3),
                textColor: isActive ? .white : .primary,
                fontSize: 20,
                fontWeight: .medium
            )

            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                HStack(spacing: AppDesign.Spacing.sm) {
                    Text(profile.name)
                        .font(AppDesign.Font.rowTitle)
                        .foregroundColor(.primary)
                    if isActive {
                        Text(localization.L(L10n.Profiles.active))
                            .font(AppDesign.Font.iconXS(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                // La carte à chiffres clés de la spec refonte (§6) : ce qui
                // décide si on active ce profil se lit en colonnes tenues,
                // pas en phrases empilées — trois colonnes de ~85 pt tiennent
                // dans les ~280 pt que la fenêtre minimale (820 pt) laisse
                // à côté de l'avatar et des boutons.
                statColumns
                // Pastilles d'attention sur leur propre ligne, sous les
                // colonnes : la pastille FR reste la seule porte vers le
                // diagnostic sur un profil sans le moindre défaut, et son
                // libellé (« FR 86 % · 50 à traduire ») ne se replie pas en
                // colonne.
                translationBadge
                configBadge
            }

            Spacer()

            // Activate → switch to this profile (applies its mod set). Hidden
            // for the already-active profile, and disabled while another
            // application is still moving files (activation is serialized).
            // While *this* profile is the one being applied, its Activate
            // button collapses to a spinner.
            // Le profil devient actif **avant** que ses dossiers ne bougent :
            // tester `applyingProfileId` d'abord, sinon le témoin d'activité
            // vivrait dans une branche `!isActive` que l'application ne
            // traverse jamais.
            if vm.applyingProfileId == profile.id {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 70, alignment: .center)
            } else if !isActive {
                Button(localization.L(L10n.Profiles.activate)) { onApply() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.isApplyingProfile)
                    .pointingHandCursor()
            }

            // Manage → apply this profile and jump to the Mods page to edit it.
            Button(localization.L(L10n.Profiles.manageMods)) { onManage() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isApplyingProfile)
                .pointingHandCursor()

            // Overflow: rename / delete. The default profile can't be deleted,
            // so its menu only offers rename.
            Menu {
                Button(localization.L(L10n.Profiles.rename)) { onRename() }
                Button(localization.L(L10n.Profiles.duplicate)) { onDuplicate() }
                // Refusée pendant qu'un profil s'applique : le profil devient
                // actif **avant** que ses dossiers ne bougent, un import lancé
                // dans cette fenêtre courserait les déplacements en cours.
                Button(localization.L(L10n.Profiles.importFavorites)) { onImportFavorites() }
                    .disabled(vm.isApplyingProfile)
                Button(localization.L(L10n.Profiles.importBlacklisted)) { onImportBlacklisted() }
                    .disabled(vm.isApplyingProfile)
                if !vm.isDefaultProfile(profile.id) {
                    Divider()
                    Button(localization.L(L10n.Profiles.delete), role: .destructive) { onDelete() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: AppDesign.Font.scaled(15)))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(localization.L(L10n.Mods.moreActions))
        }
        .padding(.vertical, AppDesign.Spacing.md)
        .padding(.horizontal, AppDesign.Spacing.lg)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(AppDesign.Opacity.subtle) : Color.clear)
        .onHover { isHovered = $0 }
        .onAppear { configSummary = vm.profileConfigSummary(for: profile) }
        .contextMenu {
            if !isActive {
                Button(localization.L(L10n.Profiles.activate)) { onApply() }
                    .disabled(vm.isApplyingProfile)
            }
            Button(localization.L(L10n.Profiles.manageMods)) { onManage() }
                .disabled(vm.isApplyingProfile)
            Button(localization.L(L10n.Profiles.rename)) { onRename() }
            Button(localization.L(L10n.Profiles.duplicate)) { onDuplicate() }
            Button(localization.L(L10n.Profiles.importFavorites)) { onImportFavorites() }
                .disabled(vm.isApplyingProfile)
            Button(localization.L(L10n.Profiles.importBlacklisted)) { onImportBlacklisted() }
                .disabled(vm.isApplyingProfile)
            if !vm.isDefaultProfile(profile.id) {
                Divider()
                Button(localization.L(L10n.Profiles.delete), role: .destructive) { onDelete() }
            }
        }
    }

    /// Les trois chiffres qui résument le profil (spec refonte §6, « carte à
    /// chiffres clés »). Chaque colonne : libellé `footnote` au-dessus,
    /// valeur `body` semibold en dessous — le motif `StatStrip` en
    /// miniature, à hauteur réservée : une colonne sans données affiche
    /// « — », la rangée ne saute pas.
    ///
    /// Seule « Anomalies » est un bouton : c'est la donnée qui mène au
    /// diagnostic, la cible de clic est donc la colonne entière, pas un
    /// glyph de 12 pt (a11y §7). « 0 » s'affiche neutre — un zéro est une
    /// information ; « > 0 » porte glyph **et** couleur, jamais la couleur
    /// seule (P6).
    private var statColumns: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.xl) {
            StatColumn(label: localization.L(L10n.Profiles.colMods),
                       value: "\(modCount)",
                       help: String(format: localization.L(L10n.Profiles.modCount), modCount))
            Button(action: onShowMissing) {
                StatColumn(label: localization.L(L10n.Profiles.colIssues),
                           value: "\(issueCount)",
                           attention: issueCount > 0,
                           help: String(format: localization.L(L10n.Profiles.issuesBadge),
                                        Int64(issueCount)))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            StatColumn(label: localization.L(L10n.Profiles.colConfigs),
                       value: configSummary.total > 0 ? "\(configSummary.total)" : "—")
        }
        .fixedSize()
    }

    /// Les `config.json` que ce profil retient, et ceux dont le mod n'est
    /// plus installé.
    ///
    /// Sa propre ligne, comme `translationBadge` : la rangée ne tient pas
    /// un compteur de plus à la largeur minimale de la fenêtre. Les noms
    /// d'orphelins sont tronqués à cinq — un profil peut en porter des
    /// dizaines.
    @ViewBuilder
    private var configBadge: some View {
        if configSummary.total > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: localization.L(L10n.Profiles.configStored),
                            Int64(configSummary.total)))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                if !configSummary.orphans.isEmpty {
                    let names = configSummary.orphans.prefix(5).joined(separator: ", ")
                    let more = configSummary.orphans.count - 5
                    Text(String(format: localization.L(L10n.Profiles.configOrphans),
                                Int64(configSummary.orphans.count),
                                more > 0 ? "\(names) +\(more)" : names))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// La part de français du profil, et ce qu'il reste à traduire.
    ///
    /// Elle n'informe pas seulement : c'est **la seule porte** vers l'écran de
    /// diagnostic quand le profil n'a ni mod manquant ni dépendance en
    /// souffrance — la pastille orange ne s'affiche alors pas. Sur ses trois
    /// profils c'est le cas de « TEST », qui compte pourtant 15 mods sans une
    /// ligne de français.
    ///
    /// Rien pour un profil qui n'a aucun mod traduisible : annoncer « 0 % »
    /// ferait croire à un travail qui n'existe pas.
    @ViewBuilder
    private var translationBadge: some View {
        if let summary = translation, !summary.isEmpty {
            Button(action: onShowMissing) {
                HStack(spacing: 4) {
                    CoverageRing(fraction: Double(summary.displayPercent) / 100,
                                 tint: summary.pending.isEmpty ? AppDesign.Color.success : AppDesign.Color.accent)
                    Text(summary.pending.isEmpty
                         ? String(format: localization.L(L10n.Profiles.frBadgeDone), summary.displayPercent)
                         : String(format: localization.L(L10n.Profiles.frBadge),
                                  summary.displayPercent, Int64(summary.pending.count)))
                }
                .font(AppDesign.Font.footnote(.medium))
                .foregroundColor(summary.pending.isEmpty ? .secondary : .accentColor)
                // Le libellé le plus long — « FR 100 % · 999 à traduire » —
                // reste sur une ligne : la colonne le tient, mais rien ne doit
                // pouvoir le replier en deux si un profil grossit encore.
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(String(format: localization.L(L10n.Profiles.frBadgeHint),
                         Int64(summary.translatableCount),
                         Int64(summary.fullyTranslatedCount)))
        } else if isMeasuringTranslation {
            // Sans texte : trois lignes de profil afficheraient sinon trois
            // fois la même phrase. L'infobulle la porte pour qui s'interroge.
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
                .help(localization.L(L10n.Profiles.translationMeasuring))
        }
    }
}
