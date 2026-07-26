import SwiftUI

// SystemStatusFooter.swift
// Résumé compact affiché en bas du sidebar (avant le Spacer final).
// Visible en permanence, donne un aperçu immédiat de l'état du système
// sans nécessiter de clic vers l'onglet "Alertes".
//
// Trois indicateurs :
//   - Mods actifs (vert) : nombre de mods activés / total
//   - Updates (orange)   : mises à jour SMAPI + Nexus disponibles
//   - Errors (rouge)     : erreurs SMAPI détectées (masqué si 0)

struct SystemStatusFooter: View {
    @ObservedObject var vm: StarHubTHViewModel

    private var enabledCount: Int { vm.mods.filter(\.isEnabled).count }
    private var updatesCount: Int { vm.outOfDateMods.count + vm.nexusUpdates.count }
    private var errorsCount: Int { vm.smapiErrors.count }

    var body: some View {
        HStack(spacing: AppDesign.Spacing.md) {
            statusPill(
                count: enabledCount,
                total: vm.mods.count,
                color: AppDesign.Color.success,
                icon: "puzzlepiece.extension"
            )
            statusPill(
                count: updatesCount,
                color: AppDesign.Color.warning,
                icon: "arrow.up.circle"
            )
            if errorsCount > 0 {
                statusPill(
                    count: errorsCount,
                    color: AppDesign.Color.error,
                    icon: "exclamationmark.triangle"
                )
            }
        }
        .padding(.horizontal, AppDesign.Spacing.sm)
        .padding(.vertical, AppDesign.Spacing.xs)
        .accessibilityLabel(
            String(
                format: vm.L(L10n.Main.systemStatusA11y),
                Int64(enabledCount),
                Int64(updatesCount),
                Int64(errorsCount)
            )
        )
    }

    /// Un indicateur compact : icône + compteur. La couleur reflète l'état
    /// (vert si tout va bien, orange/rouge si attention requise).
    private func statusPill(
        count: Int,
        total: Int? = nil,
        color: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(AppDesign.Font.iconXS)
            if let total = total {
                Text("\(count)/\(total)")
                    .font(AppDesign.Font.footnote(.medium))
                    .monospacedDigit()
            } else {
                Text("\(count)")
                    .font(AppDesign.Font.footnote(.medium))
                    .monospacedDigit()
            }
        }
        // Vert seulement si tout est actif (count == total) ; orange sinon
        // pour les updates ; rouge pour les erreurs.
        .foregroundColor(displayColor(count: count, total: total, base: color))
    }

    /// Détermine la couleur d'affichage selon le contexte :
    /// - Mods : vert si tous actifs, sinon gris discret
    /// - Updates/Errors : couleur d'alerte si count > 0, sinon gris discret
    private func displayColor(count: Int, total: Int?, base: Color) -> Color {
        if let total = total {
            // Cas "mods actifs" : vert si tout est activé, sinon discret
            return count == total && total > 0 ? base : AppDesign.Color.secondary
        } else {
            // Cas updates/errors : couleur si count > 0, sinon discret
            return count > 0 ? base : AppDesign.Color.secondary
        }
    }
}

// MARK: - Account Header Card

/// Carte d'en-tête compacte affichée en haut de la sidebar (macOS System
/// Settings style). Consolide le badge utilisateur, le profil actif et les
/// métadonnées clés (mods actifs, statut SMAPI) en une seule carte visuelle
/// hiérarchisée, remplaçant l'ancien grand avatar isolé + le
/// `SystemStatusFooter` flottant.
///
/// Structure verticale :
///   1. Ligne identité : avatar 36px + nom + sous-titre (compte Steam)
///   2. Profil actif (si défini) : capsule accent
///   3. Métadonnées : mods actifs/total + statut SMAPI
struct AccountHeaderCard: View {
    @ObservedObject var vm: StarHubTHViewModel
    let isActive: Bool
    let isHovered: Bool
    let onTap: () -> Void

    /// Profil actuellement actif (résolu depuis `activeProfileId`), ou nil.
    private var activeProfile: ModProfile? {
        vm.activeProfileId.flatMap { id in vm.modProfiles.first(where: { $0.id == id }) }
    }

    /// Nombre de mods activés sur le total installé.
    private var enabledCount: Int { vm.mods.filter(\.isEnabled).count }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // ── Ligne identité ───────────────────────────────────────
                HStack(spacing: 10) {
                    avatarView
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.steamUsername.isEmpty
                             ? vm.L(L10n.Main.playerFallback)
                             : vm.steamUsername)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(vm.L(L10n.Main.steamAccount))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                // ── Profil actif ─────────────────────────────────────────
                if let profile = activeProfile {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(profile.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }

                // ── Métadonnées : mods actifs + statut SMAPI ────────────
                HStack(spacing: 0) {
                    metricPill(
                        icon: "puzzlepiece.extension.fill",
                        value: "\(enabledCount)/\(vm.mods.count)",
                        color: vm.mods.isEmpty ? AppDesign.Color.secondary : AppDesign.Color.success
                    )
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 6)
                    metricPill(
                        icon: "app.badge.fill",
                        value: smapiLabel,
                        color: vm.smapiInstalledVersion == nil
                            ? AppDesign.Color.secondary
                            : AppDesign.Color.success
                    )
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive
                          ? Color.accentColor.opacity(0.10)
                          : (isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                            lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .help(vm.L(L10n.Main.home))
        .accessibilityElement(children: .combine)
    }

    /// Avatar utilisateur (image Steam ou icône par défaut), avec badge du
    /// profil actif superposé en bas à droite si défini.
    @ViewBuilder
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let avatarPath = vm.steamAvatarPath,
               let nsImage = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .foregroundColor(.gray)
            }
        }
    }

    /// Libellé court du statut SMAPI : version si installé, sinon "n/a".
    private var smapiLabel: String {
        if let v = vm.smapiInstalledVersion {
            return "v\(v)"
        }
        return vm.L(L10n.Home.notInstalled)
    }

    /// Une cellule de métadonnée compacte : icône + valeur. Couleur pilotée
    /// par l'appelant (vert = ok, gris = neutre/absent).
    private func metricPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(color)
    }
}
