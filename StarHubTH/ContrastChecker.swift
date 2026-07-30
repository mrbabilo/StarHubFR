import AppKit
import Foundation

// ContrastChecker.swift
// Utilitaire de vérification de contraste WCAG 2.1 (niveau AA).
// Vit dans StarHubTHCore pour être testable via SPM (utilise AppKit pour
// la résolution des couleurs système, disponible sur macOS).
//
// WCAG AA :
//   - Texte normal (< 18pt / < 14pt bold) : ratio >= 4.5:1
//   - Grand texte (>= 18pt / >= 14pt bold) : ratio >= 3:1

public enum ContrastChecker {

    /// Ratio de contraste WCAG entre deux NSColor. Retourne une valeur
    /// entre 1.0 (couleurs identiques) et 21.0 (noir sur blanc).
    public static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// True si le ratio respecte WCAG AA.
    /// - Parameters:
    ///   - largeText: true pour le seuil grand texte (3:1), false pour normal (4.5:1).
    public static func passesAA(foreground: NSColor, background: NSColor,
                                largeText: Bool = false) -> Bool {
        let threshold = largeText ? 3.0 : 4.5
        return ratio(foreground, background) >= threshold
    }

    /// True si le ratio respecte WCAG AAA (plus strict : 7:1 normal, 4.5:1 grand).
    public static func passesAAA(foreground: NSColor, background: NSColor,
                                 largeText: Bool = false) -> Bool {
        let threshold = largeText ? 4.5 : 7.0
        return ratio(foreground, background) >= threshold
    }

    /// Ajuste `color` pour atteindre au moins `target` de contraste sur
    /// `background`, en s'éloignant du fond par pas de luminosité HSB : on
    /// assombrit sur fond clair, on éclaircit sur fond sombre. Teinte et
    /// saturation sont conservées.
    ///
    /// L'ajustement est borné à [0.1, 0.9] en luminosité — on ne pousse jamais
    /// au noir/blanc pur, ce qui trahirait l'intention de couleur de l'auteur.
    /// Si le ratio reste inatteignable dans cette plage (typiquement un gris
    /// moyen sur fond gris moyen), renvoie `nil` : l'appelant retombe alors sur
    /// la couleur de texte par défaut plutôt que de rendre illisible.
    public static func adjusted(_ color: NSColor,
                                on background: NSColor,
                                toAtLeast target: Double = 4.5) -> NSColor? {
        if ratio(color, background) >= target { return color }
        let bg = background.usingColorSpace(.sRGB) ?? background
        let base = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // S'éloigner du fond : fond clair → assombrir, fond sombre → éclaircir.
        let darken = relativeLuminance(bg) > 0.2
        var value = b
        let step: CGFloat = 0.05
        var safety = 0
        while safety < 40 {
            safety += 1
            value = darken ? max(0.1, value - step) : min(0.9, value + step)
            let candidate = NSColor(hue: h, saturation: s, brightness: value, alpha: a)
            if ratio(candidate, background) >= target { return candidate }
            // On s'arrête à la borne opposée seulement (assombrir → plancher 0.1,
            // éclaircir → plafond 0.9) ; sinon un point de départ proche de 0.9
            // casserait la boucle avant d'avoir essayé les valeurs utiles.
            let reachedBound = darken ? (value <= 0.1) : (value >= 0.9)
            if reachedBound { break }
        }
        return nil
    }

    /// Table des noms de couleurs BBCode usuels → `NSColor`. Un nom inconnu
    /// renvoie `nil` : le texte reste dans la couleur par défaut.
    public static func color(named name: String) -> NSColor? {
        switch name.lowercased() {
        case "red":    return .systemRed
        case "green":  return .systemGreen
        case "blue":   return .systemBlue
        case "yellow": return .systemYellow
        case "orange": return .systemOrange
        case "purple": return .systemPurple
        case "pink":   return .systemPink
        case "brown":  return .systemBrown
        case "cyan", "teal": return .systemCyan
        case "black":  return .black
        case "white":  return .white
        case "gray", "grey": return .systemGray
        default:       return nil
        }
    }

    /// Luminance relative WCAG d'une couleur. Convertit en sRGB puis applique
    /// la formule gamma corrigée.
    private static func relativeLuminance(_ color: NSColor) -> Double {
        // Résoudre en sRGB pour avoir des composantes RGB stables.
        let c = color.usingColorSpace(.sRGB) ?? NSColor.black
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = channel(Double(c.redComponent))
        let g = channel(Double(c.greenComponent))
        let b = channel(Double(c.blueComponent))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
