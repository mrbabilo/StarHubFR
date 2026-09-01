import SwiftUI
import Testing
@testable import StarHubTHCore

@Suite struct SaveFarmerPaletteTests {
    @Test func skinColorClamping() {
        let indices = [-1, 0, 23, 24, 99, Int.max]
        for i in indices {
            let resolved = SaveFarmerPalette.skinColor(for: i)
            let expected = SaveFarmerPalette.skinColors[max(0, min(i, SaveFarmerPalette.skinColors.count - 1))]
            #expect(resolved == expected)
        }
        // Toutes les couleurs retournées doivent provenir du tableau de référence.
        for i in indices {
            let resolved = SaveFarmerPalette.skinColor(for: i)
            let isInPalette = SaveFarmerPalette.skinColors.contains(where: { $0 == resolved })
            #expect(isInPalette)
        }
    }

    @Test func hairColorConvertsTheSaveRGB() {
        // La save porte la couleur effective (`<hairstyleColor>` R/G/B 0-255),
        // pas un index de palette : la conversion est une normalisation
        // directe, et le clamp est déjà celui de `SaveHairColor.init`.
        let raw = SaveHairColor(r: 27, g: 81, b: 108)
        let expected = Color(red: 27.0 / 255.0, green: 81.0 / 255.0, blue: 108.0 / 255.0)
        #expect(SaveFarmerPalette.hairColor(from: raw) == expected)

        #expect(SaveFarmerPalette.hairColor(from: .default) ==
               SaveFarmerPalette.hairColor(from: SaveHairColor(r: 90, g: 73, b: 38)))
    }

    @Test func hatShapeBald() {
        #expect(SaveFarmerPalette.hatShape(for: 0) == .bald)
    }

    @Test func hatShapeShort() {
        #expect(SaveFarmerPalette.hatShape(for: 1) == .short)
        #expect(SaveFarmerPalette.hatShape(for: 15) == .short)
        #expect(SaveFarmerPalette.hatShape(for: 31) == .short)
    }

    @Test func hatShapeLong() {
        #expect(SaveFarmerPalette.hatShape(for: 32) == .long)
        #expect(SaveFarmerPalette.hatShape(for: 63) == .long)
        #expect(SaveFarmerPalette.hatShape(for: 95) == .long)
    }

    @Test func hatShapeWrap() {
        // Seuils résolus à 40×40 px : au-delà, le delta visuel entre 32 et 95
        // est imperceptible ; on retombe sur `.short` plutôt que d'inventer une 4ᵉ forme.
        #expect(SaveFarmerPalette.hatShape(for: 96) == .short)
        #expect(SaveFarmerPalette.hatShape(for: 161) == .short)
        #expect(SaveFarmerPalette.hatShape(for: Int.max) == .short)
    }

    @Test func hatShapeNegative() {
        #expect(SaveFarmerPalette.hatShape(for: -1) == .short)
    }
}