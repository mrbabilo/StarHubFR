import SwiftUI

// Le bloc « compatibilité smapi.io » de la carte de santé, sorti du fichier
// principal le 2026-09-25 quand ses lignes ont reçu leurs actions (fiche,
// lien proposé, journal).
extension SmapiHealthCard {

    /// D'où viennent les verdicts affichés (A2-T3) : permet au bandeau de
    /// signaler la fraîcheur de la source. Une lecture depuis le cache disque
    /// d'il y a huit heures n'a pas le même poids qu'un verdict tout juste
    /// sorti de smapi.io, et l'utilisateur a le droit de savoir.
    @ViewBuilder
    var compatibilitySourceBadge: some View {
        switch vm.compatibilitySource {
        case .live:
            pill(text: localization.L(L10n.Mods.compatSourceLive), color: .green)
        case .pathoschildDump:
            pill(text: String(format: localization.L(L10n.Mods.compatSourcePathoschild),
                              PathoschildDateLabel.string(from: vm.pathoschildDumpDate)),
                 color: .orange)
        case .diskCache:
            pill(text: String(format: localization.L(L10n.Mods.compatSourceCache),
                              PathoschildDateLabel.string(from: vm.pathoschildDumpDate)),
                 color: .secondary)
        case .none:
            EmptyView()
        }
    }

    private func pill(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(AppDesignCore.Opacity.medium))
        .foregroundColor(color)
        .cornerRadius(AppDesignCore.Radius.sm)
    }

    /// Ce que smapi.io dit de la compatibilité du parc.
    ///
    /// **Les deux chiffres vont ensemble, et le second n'est pas décoratif** :
    /// sur le parc de référence, sept mods sont signalés et **552 sur 840 sont
    /// inconnus** de smapi.io. Montrer les sept sans dire les 552 laisserait
    /// croire que le reste est vérifié sain, ce que personne n'a établi.
    @ViewBuilder
    var compatibilityBlock: some View {
        let flagged = vm.compatibilityFlaggedMods
        let unknown = vm.compatibilityUnknownCount
        if !flagged.isEmpty || unknown > 0 {
            sectionCard(flagged.isEmpty ? .secondary : .red) {
                sectionTitle(String(format: localization.L(L10n.Mods.compatHealthFlagged), flagged.count),
                             icon: "exclamationmark.triangle.fill",
                             color: flagged.isEmpty ? .secondary : .red,
                             trailing: { AnyView(compatibilitySourceBadge) })
                ForEach(flagged.prefix(8), id: \.name) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(CompatibilityWarning.label(entry.verdict.status, localization))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(CompatibilityWarning.tint(entry.verdict.status))
                        if let brokeIn = entry.verdict.brokeIn {
                            Text(String(format: localization.L(L10n.Mods.compatBrokeIn), brokeIn))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        compatActions(entry.folderName, name: entry.name, links: entry.verdict.links)
                    }
                }
                if unknown > 0 {
                    Text(String(format: localization.L(L10n.Mods.compatHealthUnknown), unknown))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Un mod que smapi.io juge cassé ou abandonné : sa fiche (onglet État,
    /// qui détaille le verdict), le lien que smapi.io propose (version non
    /// officielle, remplaçant) s'il y en a un, et ses lignes du journal.
    /// La fiche passe par `pendingModDetailFocus` : poser la fiche puis
    /// changer d'onglet serait effacé (patron B3-T4).
    func compatActions(_ folderName: String, name: String,
                               links: [ModCompatibility.Link]) -> some View {
        HStack(spacing: 2) {
            actionButton("info.circle", help: L10n.Mods.openDetails) {
                vm.navigationStore.pendingModDetailFocus = folderName
                vm.navigationStore.pendingDetailTab = .state
                vm.navigationStore.requestTab(.mods)
            }
            if let link = links.first, let url = URL(string: link.url) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .iconHelp(link.label)
            }
            actionButton("text.magnifyingglass", help: L10n.Logs.healthShowInLog) {
                NotificationCenter.default.post(name: .filterLogsToMod, object: name)
            }
        }
    }
}
