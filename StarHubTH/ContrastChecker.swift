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
