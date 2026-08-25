import SwiftUI

/// Ce que smapi.io dit d'un mod cassé, montré au seul endroit où ça change une
/// décision, et à celui où on va le chercher.
///
/// **Mesuré avant d'être écrit** : sur 840 mods interrogés, sept sont signalés,
/// et les sept étaient déjà en pause — l'utilisateur les avait diagnostiqués
/// lui-même, ses noms de dossier en témoignent. Un bandeau posé sur une fiche
/// ne lui apprend donc rien qu'il ne sache. L'avertissement ne paie qu'au
/// moment où il **active** un de ces mods, ou en **installe** un huitième :
/// c'est là qu'il est monté, et le bandeau ne fait que rendre consultable ce
/// que l'alerte a dit en passant.
enum CompatibilityWarning {

    /// Le libellé du verdict.
    static func label(_ status: ModCompatibility.Status, _ vm: StarHubTHViewModel) -> String {
        switch status {
        case .broken:     return vm.L(L10n.Mods.compatStatusBroken)
        case .abandoned:  return vm.L(L10n.Mods.compatStatusAbandoned)
        case .obsolete:   return vm.L(L10n.Mods.compatStatusObsolete)
        case .unofficial: return vm.L(L10n.Mods.compatStatusUnofficial)
        case .workaround: return vm.L(L10n.Mods.compatStatusWorkaround)
        case .ok:         return ""
        }
    }

    /// La couleur du verdict : rouge quand rien n'est proposé pour remplacer le
    /// mod, orange quand la phrase désigne une sortie.
    static func tint(_ status: ModCompatibility.Status) -> Color {
        status.severity >= ModCompatibility.Status.obsolete.severity ? .red : .orange
    }

    /// Le corps du message : d'où vient la casse, puis ce que smapi.io conseille.
    ///
    /// `brokeIn` d'abord — c'est lui qui transforme « ce mod a planté » en
    /// « ce mod est cassé depuis la 1.6 », le passage que l'axe A2 se donne
    /// pour critère de réussite.
    static func message(_ verdict: ModCompatibility, component: ModItem, host: ModItem,
                        vm: StarHubTHViewModel) -> String {
        var lines: [String] = []
        if let brokeIn = verdict.brokeIn {
            lines.append(String(format: vm.L(L10n.Mods.compatBrokeIn), brokeIn))
        }
        // Un pack nomme celui de ses composants qui est en cause : c'est le
        // dossier de premier niveau qu'on active, mais l'enfant qu'il faut
        // savoir regarder.
        if host.isGroup, component.uniqueId != host.uniqueId {
            lines.append(String(format: vm.L(L10n.Mods.compatInPack), component.name))
        }
        if !verdict.summary.isEmpty { lines.append(verdict.summary) }
        return lines.joined(separator: "\n")
    }
}

/// Le bandeau permanent de la fiche d'un mod.
struct CompatibilityBanner: View {
    @ObservedObject var vm: StarHubTHViewModel
    let mod: ModItem

    var body: some View {
        if let warning = vm.compatibilityWarning(for: mod) {
            let tint = CompatibilityWarning.tint(warning.verdict.status)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(tint)
                    Text(CompatibilityWarning.label(warning.verdict.status, vm))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tint)
                    Text(vm.L(L10n.Mods.compatSource))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                let body = CompatibilityWarning.message(warning.verdict,
                                                        component: warning.component,
                                                       host: mod, vm: vm)
                if !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Les liens de la phrase, en boutons : c'est là qu'est l'action
                // — le champ `unofficial` de l'API, lui, pointe vers la page
                // qui vient de répondre.
                if !warning.verdict.links.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(warning.verdict.links.prefix(2), id: \.url) { link in
                            Button(link.label) {
                                if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .pointingHandCursor()
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.10)))
            .padding(.top, 4)
        }
    }
}

extension View {
    /// Interpose l'avertissement avant une **activation**, jamais avant une
    /// mise en pause : mettre en pause un mod cassé est précisément ce qu'il
    /// faut faire, et le confirmer serait une friction pure.
    ///
    /// L'alerte n'active rien d'elle-même : ouvrir un lien la ferme, et le mod
    /// reste dans l'état où il était. C'est voulu — aller voir le remplaçant
    /// est une réponse aussi valable que passer outre.
    func compatibilityGate(vm: StarHubTHViewModel,
                           pending: Binding<ModItem?>,
                           onConfirm: @escaping (ModItem) -> Void) -> some View {
        alert(vm.L(L10n.Mods.compatEnableTitle),
              isPresented: Binding(get: { pending.wrappedValue != nil },
                                   set: { if !$0 { pending.wrappedValue = nil } })) {
            if let mod = pending.wrappedValue, let warning = vm.compatibilityWarning(for: mod) {
                ForEach(warning.verdict.links.prefix(2), id: \.url) { link in
                    Button(link.label) {
                        if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
                        pending.wrappedValue = nil
                    }
                }
                Button(vm.L(L10n.Mods.compatEnableConfirm)) {
                    let target = mod
                    pending.wrappedValue = nil
                    onConfirm(target)
                }
                Button(vm.L(L10n.ModInstall.cancel), role: .cancel) { pending.wrappedValue = nil }
            }
        } message: {
            if let mod = pending.wrappedValue, let warning = vm.compatibilityWarning(for: mod) {
                Text(CompatibilityWarning.label(warning.verdict.status, vm) + "\n"
                     + CompatibilityWarning.message(warning.verdict,
                                                    component: warning.component,
                                                    host: mod, vm: vm))
            }
        }
    }
}
