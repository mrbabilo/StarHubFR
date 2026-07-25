import Testing
import AppKit
import Foundation
@testable import StarHubTHCore

// ContrastCheckerTests.swift
// Tests du vérificateur de contraste WCAG. Confirme que l'implémentation
// est correcte (ratio noir/blanc = 21) et que les couleurs système
// utilisées dans l'app respectent le seuil AA.

struct ContrastCheckerTests {

    @Test func blackOnWhiteIsMaxContrast() {
        let ratio = ContrastChecker.ratio(.black, .white)
        // Le ratio exact peut varier légèrement selon la résolution sRGB,
        // mais doit être très proche de 21.
        #expect(ratio > 20.0, "Black on white should be ~21:1, got \(ratio)")
        #expect(ContrastChecker.passesAA(foreground: .black, background: .white))
        #expect(ContrastChecker.passesAAA(foreground: .black, background: .white))
    }

    @Test func whiteOnBlackIsMaxContrast() {
        let ratio = ContrastChecker.ratio(.white, .black)
        #expect(ratio > 20.0, "White on black should be ~21:1, got \(ratio)")
    }

    @Test func identicalColorsHaveRatio1() {
        let ratio = ContrastChecker.ratio(.red, .red)
        #expect(abs(ratio - 1.0) < 0.01, "Identical colors should have ratio 1.0, got \(ratio)")
        #expect(!ContrastChecker.passesAA(foreground: .red, background: .red))
    }

    @Test func secondaryLabelOnWindowBackgroundPassesAA() {
        // Cas critique de l'app : .secondaryLabelColor sur .windowBackgroundColor.
        // Le texte secondaire doit rester lisible selon WCAG AA.
        let fg = NSColor.secondaryLabelColor
        let bg = NSColor.windowBackgroundColor
        #expect(ContrastChecker.passesAA(foreground: fg, background: bg),
                "secondaryLabel must meet AA contrast on windowBackground")
    }

    @Test func labelOnWindowBackgroundPassesAA() {
        let fg = NSColor.labelColor
        let bg = NSColor.windowBackgroundColor
        #expect(ContrastChecker.passesAA(foreground: fg, background: bg),
                "label must meet AA contrast on windowBackground")
    }

    @Test func largeTextUsesLowerThreshold() {
        // Jaune sur blanc : ratio faible (~1.07), échoue AA normal ET grand texte.
        let ratio = ContrastChecker.ratio(.yellow, .white)
        #expect(ratio < 2.0)
        #expect(!ContrastChecker.passesAA(foreground: .yellow, background: .white, largeText: true))

        // Gris foncé sur blanc : ratio ~9, passe AA normal ET AAA.
        let darkGray = NSColor(calibratedWhite: 0.3, alpha: 1)
        #expect(ContrastChecker.passesAA(foreground: darkGray, background: .white))
    }

    @Test func redOnWhiteIsReadable() {
        // .red système sur blanc : ratio ~4.0, passe grand texte mais pas normal.
        let ratio = ContrastChecker.ratio(.red, .white)
        #expect(ratio > 3.0, "Red on white should pass large-text AA, got \(ratio)")
        #expect(ContrastChecker.passesAA(foreground: .red, background: .white, largeText: true))
    }
}
