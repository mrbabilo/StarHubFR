import SwiftUI

/// Valeurs RGB reproduisant les palettes SDV couramment admises par les
/// éditeurs de sauvegarde (référence non-officielle, similarité non prouvée).
/// StarHubFR ne redistribue aucun asset binaire du jeu.
enum SaveFarmerPalette {
    /// 24 couleurs de peau SDV vanilla (indices 0-23).
    static let skinColors: [Color] = [
        Color(red: 0.976, green: 0.682, blue: 0.537, opacity: 1.0), // 0 light tan
        Color(red: 0.882, green: 0.549, blue: 0.400, opacity: 1.0), // 1
        Color(red: 0.941, green: 0.627, blue: 0.510, opacity: 1.0), // 2
        Color(red: 0.969, green: 0.725, blue: 0.604, opacity: 1.0), // 3
        Color(red: 0.769, green: 0.392, blue: 0.278, opacity: 1.0), // 4
        Color(red: 0.682, green: 0.373, blue: 0.224, opacity: 1.0), // 5
        Color(red: 0.635, green: 0.275, blue: 0.071, opacity: 1.0), // 6
        Color(red: 0.824, green: 0.541, blue: 0.231, opacity: 1.0), // 7
        Color(red: 0.741, green: 0.475, blue: 0.267, opacity: 1.0), // 8
        Color(red: 1.000, green: 0.671, blue: 0.698, opacity: 1.0), // 9 pink
        Color(red: 0.839, green: 0.698, blue: 0.663, opacity: 1.0), // 10
        Color(red: 0.910, green: 0.541, blue: 0.369, opacity: 1.0), // 11
        Color(red: 0.886, green: 0.886, blue: 0.694, opacity: 1.0), // 12 pale
        Color(red: 0.937, green: 0.549, blue: 0.627, opacity: 1.0), // 13
        Color(red: 0.549, green: 0.329, blue: 0.161, opacity: 1.0), // 14
        Color(red: 0.855, green: 0.514, blue: 0.329, opacity: 1.0), // 15
        Color(red: 0.408, green: 0.749, blue: 0.910, opacity: 1.0), // 16 blue
        Color(red: 0.741, green: 0.910, blue: 0.533, opacity: 1.0), // 17 green
        Color(red: 1.000, green: 0.557, blue: 0.557, opacity: 1.0), // 18
        Color(red: 0.698, green: 0.569, blue: 1.000, opacity: 1.0), // 19 purple
        Color(red: 1.000, green: 0.867, blue: 0.549, opacity: 1.0), // 20 yellow
        Color(red: 0.867, green: 0.824, blue: 0.827, opacity: 1.0), // 21
        Color(red: 1.000, green: 0.804, blue: 0.620, opacity: 1.0), // 22
        Color(red: 1.000, green: 0.827, blue: 0.710, opacity: 1.0)  // 23
    ]

    /// 32 couleurs de cheveux SDV vanilla (indices 0-31).
    static let hairColors: [Color] = [
        Color(red: 0.353, green: 0.286, blue: 0.149, opacity: 1.0), // 0 dark brown
        Color(red: 0.490, green: 0.353, blue: 0.110, opacity: 1.0), // 1
        Color(red: 0.604, green: 0.314, blue: 0.043, opacity: 1.0), // 2 auburn
        Color(red: 0.553, green: 0.388, blue: 0.114, opacity: 1.0), // 3
        Color(red: 0.604, green: 0.624, blue: 0.624, opacity: 1.0), // 4 gray
        Color(red: 0.561, green: 0.388, blue: 0.345, opacity: 1.0), // 5
        Color(red: 0.910, green: 0.937, blue: 1.000, opacity: 1.0), // 6 white
        Color(red: 0.149, green: 0.149, blue: 0.149, opacity: 1.0), // 7 black
        Color(red: 0.275, green: 0.110, blue: 0.110, opacity: 1.0), // 8 dark red
        Color(red: 0.604, green: 0.000, blue: 0.737, opacity: 1.0), // 9 magenta
        Color(red: 0.557, green: 0.114, blue: 0.918, opacity: 1.0), // 10
        Color(red: 0.604, green: 0.314, blue: 0.043, opacity: 1.0), // 11
        Color(red: 0.388, green: 0.165, blue: 0.078, opacity: 1.0), // 12
        Color(red: 0.043, green: 0.388, blue: 0.706, opacity: 1.0), // 13 blue
        Color(red: 0.196, green: 0.522, blue: 0.188, opacity: 1.0), // 14 green
        Color(red: 0.443, green: 0.027, blue: 0.153, opacity: 1.0), // 15 wine
        Color(red: 0.196, green: 0.522, blue: 0.604, opacity: 1.0), // 16
        Color(red: 0.667, green: 0.506, blue: 0.769, opacity: 1.0), // 17 lavender
        Color(red: 0.949, green: 0.949, blue: 0.949, opacity: 1.0), // 18 platinum
        Color(red: 0.690, green: 0.541, blue: 0.220, opacity: 1.0), // 19 blond
        Color(red: 0.345, green: 0.310, blue: 0.302, opacity: 1.0), // 20
        Color(red: 0.682, green: 0.475, blue: 0.451, opacity: 1.0), // 21
        Color(red: 0.349, green: 0.380, blue: 0.671, opacity: 1.0), // 22
        Color(red: 0.690, green: 0.443, blue: 0.302, opacity: 1.0), // 23
        Color(red: 0.984, green: 0.510, blue: 0.459, opacity: 1.0), // 24
        Color(red: 1.000, green: 0.608, blue: 0.529, opacity: 1.0), // 25
        Color(red: 0.231, green: 0.231, blue: 0.345, opacity: 1.0), // 26 navy
        Color(red: 0.345, green: 0.078, blue: 0.114, opacity: 1.0), // 27
        Color(red: 0.475, green: 0.349, blue: 0.224, opacity: 1.0), // 28
        Color(red: 0.110, green: 0.220, blue: 0.078, opacity: 1.0), // 29
        Color(red: 0.851, green: 0.671, blue: 0.502, opacity: 1.0)  // 30 sandy
    ]

    static func skinColor(for index: Int) -> Color {
        let i = max(0, min(index, skinColors.count - 1))
        return skinColors[i]
    }

    static func hairColor(for index: Int) -> Color {
        let i = max(0, min(index, hairColors.count - 1))
        return hairColors[i]
    }

    enum HatShape: Sendable, Equatable {
        case bald, short, long
    }

    /// 3 formes de chapeau suffisent à 40×40 px. Seuils résolus à cette taille :
    /// au-delà, le delta visuel entre 32 et 95 est imperceptible.
    static func hatShape(for hairStyle: Int) -> HatShape {
        if hairStyle == 0 { return .bald }
        if hairStyle < 0 || hairStyle >= 96 { return .short } // wrap (incl. négatifs)
        if hairStyle < 32 { return .short }
        return .long
    }
}