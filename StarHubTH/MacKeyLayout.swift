import Foundation
import Carbon.HIToolbox

/// Ce que la disposition clavier **courante** donne à une touche
/// (`UCKeyTranslate`, mode display) — l'entrée de
/// `MacKeyCodeMap.capturedName` : le jeu lit le libellé, pas la position.
/// Partagé par la capture (`ModKeybindField`) et la vue clavier du rapport
/// (`KeybindKeyboardView`) : une seule traduction, deux lecteurs.
/// Cache par source de saisie — la disposition ne change pas à chaque
/// rendu.
enum MacKeyLayout {
    private static let lock = NSLock()
    private static var sourceID = ""
    private static var cache: [Int: String?] = [:]

    /// Le caractère de la touche, sans modificateur ou avec Maj (la légende
    /// du haut d'une touche de chiffre). `nil` quand la disposition n'en
    /// produit pas (F8, flèches) ou ne se lit pas.
    static func character(for keyCode: UInt16, shift: Bool = false) -> String? {
        lock.lock(); defer { lock.unlock() }
        let current = currentSourceID()
        if current != sourceID { sourceID = current; cache = [:] }
        let slot = Int(keyCode) << 1 | (shift ? 1 : 0)
        if let cached = cache[slot] { return cached }
        let value = translate(keyCode: keyCode, shift: shift)
        cache[slot] = value
        return value
    }

    /// ISO ou ANSI, selon le clavier que macOS déclare. JIS et l'inconnu se
    /// replient sur ANSI.
    static var keyboardKind: MacKeyboardGeometry.Kind {
        KBGetLayoutType(Int16(LMGetKbdType())) == UInt32(kKeyboardISO) ? .iso : .ansi
    }

    private static func currentSourceID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID as CFString)
        else { return "" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func translate(keyCode: UInt16, shift: Bool) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData as CFString)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var units = [UniChar](repeating: 0, count: 16)
        let modifiers: UInt32 = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = layout.withUnsafeBytes { raw in
            units.withUnsafeMutableBufferPointer { buffer in
                UCKeyTranslate(raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                               keyCode, UInt16(kUCKeyActionDisplay), modifiers,
                               UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit),
                               &deadKeyState, buffer.count, &length, buffer.baseAddress!)
            }
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: units, count: length)
        // Les touches de contrôle (Entrée, tabulation…) rendent un caractère
        // invisible : pas de libellé.
        return text.unicodeScalars.allSatisfy({ $0.properties.isWhitespace || $0.value < 0x20 || $0.value == 0x7F }) ? nil : text
    }
}
