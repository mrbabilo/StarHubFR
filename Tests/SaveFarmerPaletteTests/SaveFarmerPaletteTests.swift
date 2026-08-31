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

    @Test func hairColorClamping() {
        let indices = [-1, 0, 31, 32, 99, Int.max]
        for i in indices {
            let resolved = SaveFarmerPalette.hairColor(for: i)
            let expected = SaveFarmerPalette.hairColors[max(0, min(i, SaveFarmerPalette.hairColors.count - 1))]
            #expect(resolved == expected)
        }
        for i in indices {
            let resolved = SaveFarmerPalette.hairColor(for: i)
            let isInPalette = SaveFarmerPalette.hairColors.contains(where: { $0 == resolved })
            #expect(isInPalette)
        }
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