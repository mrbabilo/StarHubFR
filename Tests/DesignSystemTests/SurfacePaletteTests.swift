import Foundation
import Testing
@testable import StarHubTHCore

struct SurfacePaletteTests {

    @Test func approvedSurfaceValuesAreExact() {
        #expect(AppDesignCore.SurfacePalette.surface == DynamicRGBColor(
            light: RGBColor(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0),
            dark: RGBColor(red: 37.0 / 255.0, green: 37.0 / 255.0, blue: 39.0 / 255.0)))
        #expect(AppDesignCore.SurfacePalette.surfaceRaised == DynamicRGBColor(
            light: RGBColor(red: 1, green: 1, blue: 1),
            dark: RGBColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 46.0 / 255.0)))
        #expect(AppDesignCore.SurfacePalette.surfaceBorder == DynamicRGBColor(
            light: RGBColor(red: 217.0 / 255.0, green: 217.0 / 255.0, blue: 222.0 / 255.0),
            dark: RGBColor(red: 71.0 / 255.0, green: 71.0 / 255.0, blue: 75.0 / 255.0)))
    }

    @Test func allSurfaceColorsAreOpaque() {
        for color in allColors {
            #expect(color.opacity == 1)
        }
    }

    @Test func surfaceColorsStayQuasiNeutral() {
        for color in allColors {
            let highest = max(color.red, max(color.green, color.blue))
            let lowest = min(color.red, min(color.green, color.blue))
            #expect(highest - lowest <= 5.0 / 255.0 + Double.ulpOfOne)
        }
    }

    @Test func raisedSurfaceIsLighterAndBaseSurfaceDiffersFromWindow() {
        let surface = AppDesignCore.SurfacePalette.surface
        let raised = AppDesignCore.SurfacePalette.surfaceRaised
        let lightWindow = RGBColor(red: 1, green: 1, blue: 1)
        let darkWindow = RGBColor(red: 30.0 / 255.0, green: 30.0 / 255.0,
                                  blue: 30.0 / 255.0)

        #expect(luminance(raised.light) > luminance(surface.light))
        #expect(luminance(raised.dark) > luminance(surface.dark))
        #expect(luminance(surface.light) != luminance(lightWindow))
        #expect(luminance(surface.dark) != luminance(darkWindow))
    }

    @Test func primaryReferenceTextPassesAA() {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        let palette = [
            AppDesignCore.SurfacePalette.surface,
            AppDesignCore.SurfacePalette.surfaceRaised,
            AppDesignCore.SurfacePalette.surfaceBorder,
        ]

        for pair in palette {
            #expect(contrastRatio(black, pair.light) >= 4.5)
            #expect(contrastRatio(white, pair.dark) >= 4.5)
        }
    }

    private var allColors: [RGBColor] {
        let palette = [
            AppDesignCore.SurfacePalette.surface,
            AppDesignCore.SurfacePalette.surfaceRaised,
            AppDesignCore.SurfacePalette.surfaceBorder,
        ]
        return palette.flatMap { [$0.light, $0.dark] }
    }

    private func contrastRatio(_ first: RGBColor, _ second: RGBColor) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func luminance(_ color: RGBColor) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }
}
