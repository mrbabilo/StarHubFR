import SwiftUI

extension PendingModUpdates {
    /// L'index des mises à jour dues, construit depuis l'état de l'app — les
    /// mêmes sources et le même filtre que le badge « Mises à jour » (X113) :
    /// lignes Nexus dues (veilles et « Je l'ai déjà » ôtées), puis relevé
    /// SMAPI que le disque ne couvre pas, résolu en dossier.
    ///
    /// Peu coûteux (quelques dizaines de lignes, quelques entrées SMAPI) : les
    /// lignes le reconstruisent — une page en montre 12 —, le filtre et ses
    /// compteurs une fois par passe.
    @MainActor static func current(_ vm: StarHubTHViewModel) -> PendingModUpdates {
        let smapi = UpdateCount.pendingEntries(outOfDate: vm.outOfDateMods) {
            vm.resolveModFolder(forLoggedName: $0)?.version
        }.compactMap { entry in
            vm.resolveModFolder(forLoggedName: entry.name).map {
                (folderName: $0.folderName, version: entry.version, url: entry.url)
            }
        }
        return PendingModUpdates(nexus: vm.nexusUpdates.map { ($0.uniqueId, $0.latestVersion) },
                                 smapi: smapi)
    }
}

/// La pastille « ↑ version » d'une ligne ou d'une carte (I-T13). Glyphe et
/// texte, jamais la couleur seule ; bleu comme le badge de la barre latérale.
struct PendingUpdateBadge: View {
    let pending: PendingModUpdates.Pending
    /// « Version disponible : … », résolu par l'appelant.
    let help: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.up.circle.fill")
            Text(pending.availableVersion)
                .lineLimit(1)
        }
        .font(AppDesign.Font.iconXS(.semibold))
        .foregroundColor(.blue)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.blue.opacity(AppDesign.Opacity.medium)))
        // Cible 18×18 : sans elle `.help` ne s'affiche jamais (piège UI).
        .frame(minWidth: 18, minHeight: 18)
        .contentShape(.rect)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
    }
}
