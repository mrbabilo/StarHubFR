import SwiftUI

/// « Journal des modifications » : les deux dernières versions du
/// `CHANGELOG.md` embarqué, une carte par version, un groupe Keep a Changelog
/// par pastille colorée (audit UX 2026-10-02).
struct AppChangelogView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @State private var releases: [ChangelogExcerpt.Release] = []
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(icon: "doc.text.fill", title: localization.L(L10n.Main.appChangelog),
                       subtitle: String(format: localization.L(L10n.Main.changelogInstalled), appVersion))
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, AppDesign.Spacing.md)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                    if let failure {
                        StateCard(icon: AppDesign.Status.warning.symbol, text: failure, actionTitle: nil) {}
                    }
                    ForEach(releases, id: \.version) { ChangelogReleaseCard(release: $0, localization: localization) }
                }
                .padding(AppDesign.Spacing.xl)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppDesign.Color.windowBg)
        .onAppear { loadChangelog() }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func loadChangelog() {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else {
            failure = localization.L(L10n.Main.changelogMissing)
            return
        }
        do {
            // Les deux dernières versions seulement : le fichier entier est un
            // historique, pas des notes de version.
            releases = ChangelogExcerpt.releases(try String(contentsOf: url, encoding: .utf8))
        } catch {
            failure = String(format: localization.L(L10n.Main.changelogReadError), error.localizedDescription)
        }
    }
}

/// Une version : son numéro et sa date, puis chaque groupe sous sa pastille.
private struct ChangelogReleaseCard: View {
    let release: ChangelogExcerpt.Release
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            HStack(spacing: AppDesign.Spacing.sm) {
                IconTile(icon: release.isUnreleased ? "hammer.fill" : "shippingbox.fill",
                         tint: release.isUnreleased ? AppDesign.Color.warning : AppDesign.Color.accent, size: 30)
                Text(release.isUnreleased ? localization.L(L10n.Main.changelogUnreleased) : release.version)
                    .font(AppDesign.Font.headline(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let date = release.date {
                    Text(date).font(AppDesign.Font.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ForEach(Array(release.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                    if group.kind != .other { chip(group.kind) }
                    ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
                            Circle().fill(tint(group.kind)).frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
                                .accessibilityHidden(true)
                            Text((try? AttributedString(markdown: entry, options: .init(
                                interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry))
                                .font(AppDesign.Font.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: AppDesign.Spacing.lg)
    }

    private func chip(_ kind: ChangelogExcerpt.Group.Kind) -> some View {
        Label(label(kind), systemImage: icon(kind))
            .font(AppDesign.Font.caption(.semibold))
            .foregroundStyle(tint(kind))
            .padding(.horizontal, AppDesign.Spacing.sm)
            .padding(.vertical, 3)
            .background(tint(kind).opacity(0.12), in: Capsule())
    }

    private func label(_ kind: ChangelogExcerpt.Group.Kind) -> String {
        switch kind {
        case .added:   return localization.L(L10n.Main.changelogAdded)
        case .changed: return localization.L(L10n.Main.changelogChanged)
        case .fixed:   return localization.L(L10n.Main.changelogFixed)
        case .removed: return localization.L(L10n.Main.changelogRemoved)
        case .other:   return ""
        }
    }

    private func icon(_ kind: ChangelogExcerpt.Group.Kind) -> String {
        switch kind {
        case .added:   return "plus.circle.fill"
        case .changed: return "arrow.triangle.2.circlepath"
        case .fixed:   return "wrench.and.screwdriver.fill"
        case .removed: return "minus.circle.fill"
        case .other:   return "circle"
        }
    }

    private func tint(_ kind: ChangelogExcerpt.Group.Kind) -> Color {
        switch kind {
        case .added:   return AppDesign.Color.success
        case .changed: return AppDesign.Color.info
        case .fixed:   return AppDesign.Color.warning
        case .removed: return AppDesign.Color.error
        case .other:   return .secondary
        }
    }
}
