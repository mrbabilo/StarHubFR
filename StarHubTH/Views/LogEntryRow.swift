import SwiftUI
import AppKit

/// Une ligne du journal (Journaux, vue par mod). Sortie de `LogsView.swift`,
/// verrouillé par le cliquet de taille, le 2026-11-11.

struct LogEntryRow: View {
    let entry: LogEntry
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Source badge. For app entries the app-badge shape stays as a
            // source cue, but it is tinted by severity (level.color) so an
            // app error/warning is no longer indistinguishable from info.
            // SMAPI entries show the level icon, also severity-colored.
            Group {
                switch entry.source {
                case .app:
                    Image(systemName: "app.badge")
                        .foregroundColor(entry.level.color)
                case .smapi:
                    Image(systemName: entry.level.icon)
                        .foregroundColor(entry.level.color)
                }
            }
            .font(AppDesign.Font.footnote)
            .frame(width: 14)
            .padding(.top, 1)

            // Timestamp
            Text(entry.timestamp)
                .font(AppDesign.Font.monoFootnote)
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                // Clickable mod name badge
                if let modName = entry.modName {
                    Button {
                        NotificationCenter.default.post(name: .jumpToMod, object: modName)
                    } label: {
                        Text(modName)
                            .font(AppDesign.Font.iconXS(.medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, AppDesignCore.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(AppDesignCore.Opacity.light))
                            .cornerRadius(AppDesignCore.Radius.sm)
                    }
                    .buttonStyle(.plain).focusRing(cornerRadius: AppDesignCore.Radius.sm)
                    .pointingHandCursor()
                }

                // Message — colored by severity for BOTH sources (previously
                // app entries were always primary, hiding errors/warnings).
                // SMAPI TRACE entries are dimmed since they're verbose/noisy.
                Text(entry.message)
                    .font(AppDesign.Font.monoCaption)
                    .foregroundColor(entry.source == .smapi && entry.level == .trace
                        ? entry.level.color.opacity(0.75)
                        : entry.level.color)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // Relevée de TRACE à ERROR par l'app (`LoggedOnceError`) : le
                // fichier brut dit TRACE, l'écran dit pourquoi il diffère.
                if LoggedOnceError.isPromoted(entry) {
                    Text(localization.L(L10n.Logs.loggedOnceNote))
                        .font(AppDesign.Font.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(localization.L(L10n.Logs.copyLine)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.formattedLine, forType: .string)
            }
        }
    }
}
