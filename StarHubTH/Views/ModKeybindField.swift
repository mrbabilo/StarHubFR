import SwiftUI
import AppKit

/// Le contrôle de capture d'un raccourci reconnu (**C4-T10**), en lieu et
/// place du champ texte libre que rendait l'éditeur pour les 466 feuilles
/// raccourci du parc.
///
/// Clic : la capture s'arme — la touche pressée, modificateurs compris,
/// devient la combinaison ; `Échap` annule, cliquer de nouveau désarme.
/// Pendant la capture, les événements clavier sont **avalés** : un
/// raccourci système (⌘Q…) ne doit pas tuer l'app au milieu d'une
/// reconfiguration. C'est un état transient, désarmé à la capture, à
/// l'annulation et au démontage de la vue.
///
/// Les modificateurs seuls n'engagent rien : leur `keyDown` précède
/// toujours celui de la touche modifiée (`Maj` puis `K`), et commettre au
/// premier presserait à moitié chaque combinaison. Ils entrent dans la
/// combinaison de la touche qui suit.
struct ModKeybindField: View {
    @ObservedObject var localization: LocalizationStore
    @Binding var combo: KeybindCombo

    @State private var capturing = false
    @State private var monitor: Any?

    private var title: String {
        if capturing { return localization.L(L10n.Settings.configKeybindCapture) }
        return combo.isEmpty ? "None" : combo.display
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if capturing { disarm() } else { arm() }
            } label: {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(localization.L(L10n.Settings.configKeybindChange))

            if !capturing, !combo.isEmpty {
                Button {
                    // `KeybindCombo` n'admet qu'un bouton connu ; la
                    // combinaison vide est valide par construction, le
                    // garde n'est là que pour l'initialiseur failable.
                    guard let empty = KeybindCombo(buttons: []) else { return }
                    combo = empty
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(localization.L(L10n.Settings.configKeybindClear))
            }
        }
        .onDisappear { disarm() }
    }

    // MARK: - La capture

    private func arm() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
        }
    }

    private func disarm() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = false
    }

    /// Rend toujours `nil` pendant la capture : la touche est consommée,
    /// elle ne doit atteindre aucun autre contrôle (ni raccourci système).
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Échap (kVK_Escape) : annuler sans rien changer.
        if event.keyCode == 53 { disarm(); return nil }
        // Un modificateur seul n'engage rien — voir l'en-tête.
        if isModifierKeyDown(event) { return nil }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var buttons: [String] = []
        if mods.contains(.shift) { buttons.append(MacKeyCodeMap.modifierNames.shift) }
        if mods.contains(.control) { buttons.append(MacKeyCodeMap.modifierNames.control) }
        if mods.contains(.option) { buttons.append(MacKeyCodeMap.modifierNames.alt) }
        if mods.contains(.command) { buttons.append(MacKeyCodeMap.modifierNames.command) }
        guard let name = MacKeyCodeMap.name(for: event.keyCode),
              let next = KeybindCombo(buttons: buttons + [name]) else {
            // Touche hors table : avalée, la capture reste armée.
            return nil
        }
        disarm()
        combo = next
        return nil
    }

    /// Le `keyDown` d'un modificateur porte son propre drapeau — `Maj` puis
    /// `K` arrive bien dans cet ordre. C'est le seul test fiable : un
    /// `keyCode` seul ne dit pas s'il vient d'être pressé ou tenu.
    private func isModifierKeyDown(_ event: NSEvent) -> Bool {
        let flag: NSEvent.ModifierFlags?
        switch event.keyCode {
        case 0x38, 0x3C: flag = .shift
        case 0x3B, 0x3E: flag = .control
        case 0x3A, 0x3D: flag = .option
        case 0x37, 0x36: flag = .command
        default: flag = nil
        }
        guard let flag else { return false }
        return event.modifierFlags.contains(flag)
    }
}
