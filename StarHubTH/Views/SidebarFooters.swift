import SwiftUI

// Pieds de la barre latérale, sortis de `SidebarComponents` (plafond de
// taille, audit UX 2026-10-16, I-T26).

// MARK: - Poids du parc (B2-T2)

/// Ce que pèsent les mods, en pied de barre latérale.
///
/// Mesuré sur le parc réel le 2026-08-24 : **16,84 Go de mods, dont 12,71 Go
/// en pause** — 746 dossiers sur 863 — pour 30 Go libres. C'est ce rapport-là
/// que la barre montre, et c'est pour lui qu'elle existe : le total seul ne
/// dit pas que les trois quarts de la place sont immobilisés par des mods
/// désactivés, alors qu'une barre coupée aux trois quarts le dit sans qu'on
/// lise un chiffre.
///
/// **La barre ne compte que les mods** (100 % = le total mesuré), partagée
/// entre actifs et en pause. La place libre reste du texte : `mods + libre`
/// ne forme pas un tout — il y a ~450 Go d'autre chose sur ce volume — et un
/// troisième segment énoncerait une proportion fausse.
///
/// Ses deux couleurs sont celles des barres d'accent de la liste des mods
/// (vert pour un mod actif, gris pour un mod en pause) : le pied de barre
/// résume la liste, il doit en parler la langue.
///
/// Rien ne s'affiche tant qu'aucun jeu n'est désigné : « 0 octet » serait faux.
/// Le téléchargement Nexus en cours, en pied de barre latérale (B2-T1).
///
/// Ce qu'il remplace : un `ProgressView()` indéterminé sur une seule ligne de
/// la page des mises à jour. Un mod de 500 Mo se téléchargeait donc en
/// silence, sans qu'on sache s'il avançait, ni combien de temps il restait, ni
/// comment l'arrêter — et le lien `nxm://` d'un compte gratuit peut arriver
/// alors que n'importe quel onglet est ouvert.
///
/// **Sans taille annoncée, il ne ment pas.** Le CDN de Nexus n'annonce pas
/// toujours `Content-Length` : la barre disparaît alors, et il ne reste que le
/// volume reçu et le débit. Une barre figée à 0 % ferait croire à un blocage.
/// Volet de téléchargement Nexus, en bas de la barre latérale : une fenêtre
/// temporaire qui ne vit que le temps d'un téléchargement (`isDownloadingFromNexus`).
/// Le contenu — mod visé, annulation, progression, débit — reste identique ;
/// seul l'habillage en fait un volet flottant plutôt qu'une ligne du pied.
struct NexusDownloadFooter: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        panel
            // Le glissement est piloté côté vue : le VM se contente de muter
            // l'état à ses deux bascules (démarrage, complétion) ; animer ici
            // n'exige aucune transaction dans le ViewModel.
            .animation(Motion.animation(.spring(response: 0.3, dampingFraction: 0.85)),
                       value: vm.isDownloadingFromNexus)
    }

    /// Volet posé seulement pendant un téléchargement : glisse depuis le bord
    /// bas de la colonne, repart en sens inverse à la complétion.
    @ViewBuilder private var panel: some View {
        if vm.isDownloadingFromNexus {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                HStack(spacing: AppDesign.Spacing.xs) {
                    Image(systemName: "arrow.down.circle")
                        .font(AppDesign.Font.iconXXS)
                    Text(headline)
                        .font(AppDesign.Font.iconXS(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // Le bouton existe **dès** la demande, avant même que le
                    // lien ne soit résolu : c'est le moment où l'on se rend
                    // compte qu'on s'est trompé de mod.
                    Button(action: { vm.cancelNexusDownload() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppDesign.Font.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .pointingHandCursor()
                    .help(localization.L(L10n.Downloads.cancel))
                }
                .foregroundStyle(.secondary)

                if let fraction = vm.nexusDownloadProgress?.fractionCompleted {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                Text(detail)
                    .font(AppDesign.Font.iconXXS.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, AppDesign.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: AppDesign.Radius.md,
                                             style: .continuous))
            .shadow(color: .black.opacity(0.12),
                    radius: AppDesign.Shadow.badge.radius,
                    y: AppDesign.Shadow.badge.y)
            // Fenêtre temporaire : entrée et sortie glissées, pas une ligne
            // de plus dans le pied.
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    /// Le mod visé, dès qu'on le connaît — **par son nom** quand l'app le
    /// connaît, faute de quoi la barre latérale n'annonçait qu'un numéro.
    private var headline: String {
        guard let modId = vm.downloadingNexusModId else {
            return localization.L(L10n.Downloads.connecting)
        }
        if let name = vm.nexusModDisplayName(for: modId) {
            return String(format: localization.L(L10n.Downloads.downloadingNamed), name)
        }
        return String(format: localization.L(L10n.Downloads.downloading), Int64(modId))
    }

    /// Volume, débit et temps restant — chacun seulement s'il est mesuré.
    /// Aucune valeur inventée : pas de « 0 o/s » au démarrage, pas d'ETA sans
    /// débit.
    private var detail: String {
        guard let progress = vm.nexusDownloadProgress else {
            return localization.L(L10n.Downloads.connecting)
        }
        var parts: [String] = []
        if let total = progress.totalBytes {
            parts.append(String(format: localization.L(L10n.Downloads.progress),
                                SharedFormatters.bytes(progress.bytesReceived), SharedFormatters.bytes(total)))
        } else {
            parts.append(String(format: localization.L(L10n.Downloads.progressUnknownTotal),
                                SharedFormatters.bytes(progress.bytesReceived)))
        }
        if let rate = progress.bytesPerSecond {
            parts.append(String(format: localization.L(L10n.Downloads.rate), SharedFormatters.bytes(Int64(rate))))
        }
        if let remaining = progress.estimatedTimeRemaining, remaining > 0 {
            parts.append(String(format: localization.L(L10n.Downloads.eta), Self.duration(remaining)))
        }
        return parts.joined(separator: " · ")
    }

    /// Une durée courte et lisible : « 45 s », « 2 min ». Le formateur du
    /// système localise les unités, ce qu'une concaténation à la main ne ferait
    /// pas.
    private static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds < 60 ? [.second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }
}

struct ModsWeightFooter: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    /// Reprises telles quelles de `ModListRow` (`Views/ModListRow.swift`) : la barre d'accent verte d'un
    /// mod actif, le gris d'un mod en pause.
    private static let activeColor = AppDesign.Color.installed
    private static let pausedColor = Color.secondary.opacity(AppDesign.Opacity.strong)

    var body: some View {
        if let sizes = vm.modsFolderSizes {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                HStack(spacing: AppDesign.Spacing.xs) {
                    Image(systemName: "internaldrive")
                        .font(AppDesign.Font.iconXXS)
                        .foregroundStyle(.secondary)
                    Text(String(format: localization.L(L10n.Main.sidebarModsWeight),
                                SharedFormatters.bytes(sizes.totalBytes)))
                        .font(AppDesign.Font.iconXS(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    if vm.isMeasuringModsFolder {
                        ProgressView().controlSize(.mini).scaleEffect(0.6)
                    }
                }

                // Sans mod en pause, il n'y a pas de partage à montrer : la
                // barre serait d'une seule couleur et sa légende d'un seul
                // point, soit une décoration. Le total et la place libre disent
                // alors tout.
                //
                // Un parc vide, lui, n'a pas de proportion du tout — et le
                // rapport vaudrait une division par zéro, qui donne une largeur
                // `NaN` : une erreur d'exécution SwiftUI, pas une barre plate.
                if sizes.totalBytes > 0, sizes.pausedBytes > 0 {
                    weightBar(sizes)
                    legend(sizes)
                }

                if let free = sizes.availableBytes {
                    Text(String(format: localization.L(L10n.Main.sidebarDiskFree), SharedFormatters.bytes(free)))
                        .font(AppDesign.Font.iconXXS.monospacedDigit())
                        // Orange quand il reste moins que ce que pèsent déjà
                        // les mods : le prochain gros mod ne rentrera pas.
                        .foregroundStyle(free < sizes.totalBytes ? AppDesign.Color.warning : Color.secondary)
                }
            }
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.bottom, AppDesign.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.a11yLabel(sizes, vm: vm))
        } else if vm.isMeasuringModsFolder {
            // Sans cet état, le pied reste vide plusieurs secondes au
            // lancement — de trois à six secondes de traversée sur 100 000
            // fichiers — et le vide se lit comme un défaut.
            HStack(spacing: AppDesign.Spacing.xs) {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
                Text(localization.L(L10n.Main.sidebarModsWeightMeasuring))
                    .font(AppDesign.Font.iconXS)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.bottom, AppDesign.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// La part active posée sur toute la largeur, qui porte la part en pause.
    ///
    /// `GeometryReader` sous une hauteur **explicite** : laissé libre dans la
    /// pile de la barre latérale, il réclamerait toute la hauteur restante et
    /// pousserait les boutons de thème et de langue hors de l'écran.
    private func weightBar(_ sizes: ModsFolderSizes) -> some View {
        let active = Double(sizes.totalBytes - sizes.pausedBytes) / Double(sizes.totalBytes)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.pausedColor)
                Capsule()
                    .fill(Self.activeColor)
                    // Un filet minimal : une part active infime doit rester
                    // visible, sinon la barre laisse croire qu'il n'y a rien
                    // d'actif du tout.
                    .frame(width: max(active > 0 ? 2 : 0, geo.size.width * active))
            }
        }
        .frame(height: 5)
    }

    /// « 4,1 Go actifs · 12,7 Go en pause », chaque part sous sa couleur.
    private func legend(_ sizes: ModsFolderSizes) -> some View {
        HStack(spacing: 5) {
            dot(Self.activeColor)
            Text(String(format: localization.L(L10n.Main.sidebarModsWeightActive),
                        SharedFormatters.bytes(sizes.totalBytes - sizes.pausedBytes)))
            dot(Self.pausedColor)
            Text(String(format: localization.L(L10n.Main.sidebarModsWeightAsleep),
                        SharedFormatters.bytes(sizes.pausedBytes)))
        }
        .font(AppDesign.Font.iconXXS.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }

    /// Une barre ne se lit pas à voix haute : le lecteur d'écran reçoit les
    /// mêmes chiffres que les lignes de texte.
    static func a11yLabel(_ sizes: ModsFolderSizes, vm: StarHubTHViewModel) -> String {
        let label = String(format: vm.localization.L(L10n.Main.sidebarModsWeightA11y),
                           SharedFormatters.bytes(sizes.totalBytes),
                           SharedFormatters.bytes(sizes.totalBytes - sizes.pausedBytes),
                           SharedFormatters.bytes(sizes.pausedBytes),
                           sizes.availableBytes.map { SharedFormatters.bytes($0) } ?? "—")
        // `children: .ignore` remplace tout ce que contient le pied de barre,
        // y compris l'indicateur de mesure en cours. Sans cet ajout, un lecteur
        // d'écran recevrait des chiffres périmés pendant les secondes qui
        // suivent chaque bascule, sans rien pour le dire.
        guard vm.isMeasuringModsFolder else { return label }
        return label + " " + vm.localization.L(L10n.Main.sidebarModsWeightMeasuring)
    }
}
