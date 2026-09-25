import SwiftUI
import AppKit
import Carbon.HIToolbox

/// La gravure d'une touche sur le clavier **courant** (`UCKeyTranslate`,
/// mode display, sans modificateur). Les `SButton` nomment des positions
/// physiques US — convention du jeu, partagée par SMAPI : le nom `Q`
/// désigne la touche gravée `a` sur un AZERTY, et c'est bien cette touche
/// que le mod écoutera. L'éditeur montre donc **les deux** : ta touche
/// d'abord, le nom enregistré ensuite. Cache par source de saisie — la
/// disposition ne change pas à chaque rendu.
private enum MacKeyLayout {
    private static let lock = NSLock()
    private static var sourceID = ""
    private static var cache: [UInt16: String?] = [:]

    /// Le caractère gravé de la touche, `nil` quand la table ne la connaît
    /// pas (`MouseLeft`, la manette) ou que la disposition n'en produit pas.
    static func keycap(for name: String) -> String? {
        guard let keyCode = MacKeyCodeMap.keyCode(for: name) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let current = currentSourceID()
        if current != sourceID { sourceID = current; cache = [:] }
        if let cached = cache[keyCode] { return cached }
        let keycap = translate(keyCode: keyCode)
        cache[keyCode] = keycap
        return keycap
    }

    private static func currentSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID as CFString)
        else { return "" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func translate(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData as CFString)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 16)
        let status = layout.withUnsafeBytes { raw in
            units.withUnsafeMutableBufferPointer { buffer in
                UCKeyTranslate(raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                               keyCode, UInt16(kUCKeyActionDisplay), 0,
                               UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit),
                               &deadKeyState, buffer.count, &length, buffer.baseAddress!)
            }
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: units, count: length)
    }
}

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
///
/// L'affichage d'une combinaison à **une** touche grave est bilingue quand
/// la gravure diffère du nom : « a · Q » — la minuscule est ta touche, la
/// majuscule le nom enregistré dans le fichier. Traduit depuis la
/// disposition courante (`MacKeyLayout`), donc vrai aussi à la réouverture,
/// pas seulement juste après une capture. Les noms sans gravure (`F8`,
/// `Space`, la manette) et les listes s'affichent tels qu'enregistrés.
struct ModKeybindField: View {
    @ObservedObject var localization: LocalizationStore
    @Binding var combo: KeybindCombo

    @State private var capturing = false
    @State private var monitor: Any?

    /// `(ta touche, le nom enregistré)` quand la gravure courante diffère
    /// du nom — `nil` quand l'un des deux suffit. Le filtre de
    /// `keycapHint` écarte ce qui n'apprend rien (QWERTY, `D1` contre `1`).
    private var layoutHint: (keycap: String, stored: String)? {
        guard !capturing, !combo.isEmpty, combo.buttons.count == 1,
              let stored = combo.buttons.first,
              let engraved = MacKeyLayout.keycap(for: stored),
              let keycap = MacKeyCodeMap.keycapHint(physicalName: stored, typedCharacter: engraved)
        else { return nil }
        return (keycap, stored)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if capturing { disarm() } else { arm() }
            } label: {
                HStack(spacing: 4) {
                    if capturing {
                        Text(localization.L(L10n.Settings.configKeybindCapture))
                    } else if let hint = layoutHint {
                        Text(hint.keycap)
                        Text("· " + hint.stored)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(combo.isEmpty ? "None" : combo.display)
                    }
                }
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
                .iconHelp(localization.L(L10n.Settings.configKeybindClear))
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
