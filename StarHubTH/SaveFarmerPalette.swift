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

    /// Couleur de cheveux effective de la save (`<hairstyleColor>` est un
    /// Color libre, pas un index : aucune palette indexée à parcourir —
    /// la table de 31 entrées d'H-T5b clampait une donnée inexistante).
    /// Les composantes sont déjà bornées 0-255 par `SaveHairColor`.
    static func hairColor(from raw: SaveHairColor) -> Color {
        Color(red: Double(raw.r) / 255.0,
              green: Double(raw.g) / 255.0,
              blue: Double(raw.b) / 255.0,
              opacity: 1.0)
    }

    static func skinColor(for index: Int) -> Color {
        let i = max(0, min(index, skinColors.count - 1))
        return skinColors[i]
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