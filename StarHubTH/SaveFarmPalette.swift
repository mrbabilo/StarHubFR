import SwiftUI

/// Palette des 8 fermes vanilla. Référence non-officielle — les couleurs
/// sont des approximations flat inspirées visuellement des thèmes vanilla.
enum SaveFarmPalette {
    static let standardBg     = Color(red: 0.659, green: 0.788, blue: 0.478, opacity: 1.0) // #A8C97A vert prairie
    static let standardAccent = Color(red: 0.298, green: 0.439, blue: 0.247, opacity: 1.0)

    static let riverlandBg    = Color(red: 0.478, green: 0.710, blue: 0.788, opacity: 1.0) // #7AB5C9 eau
    static let riverlandAccent = Color(red: 0.310, green: 0.490, blue: 0.620, opacity: 1.0)

    static let forestBg       = Color(red: 0.247, green: 0.478, blue: 0.290, opacity: 1.0) // #3F7A4A vert sombre
    static let forestAccent   = Color(red: 0.149, green: 0.310, blue: 0.196, opacity: 1.0)

    static let hilltopBg      = Color(red: 0.612, green: 0.533, blue: 0.400, opacity: 1.0) // #9C8866 terre
    static let hilltopAccent  = Color(red: 0.380, green: 0.318, blue: 0.224, opacity: 1.0)

    static let wildernessBg   = Color(red: 0.227, green: 0.227, blue: 0.290, opacity: 1.0) // #3A3A4A nuit
    static let wildernessAccent = Color(red: 0.831, green: 0.831, blue: 0.910, opacity: 0.8) // lune

    static let fourCornersBg  = Color(red: 0.851, green: 0.761, blue: 0.541, opacity: 1.0) // #D9C28A sable
    static let fourCornersAccent = Color(red: 0.580, green: 0.475, blue: 0.290, opacity: 1.0)

    static let beachBg        = Color(red: 0.941, green: 0.824, blue: 0.604, opacity: 1.0) // #F0D29A sable clair
    static let beachAccent    = Color(red: 0.380, green: 0.580, blue: 0.722, opacity: 1.0)

    static let meadowlandsBg  = Color(red: 0.616, green: 0.745, blue: 0.353, opacity: 1.0) // #9DBE5A vert tendre
    static let meadowlandsAccent = Color(red: 0.310, green: 0.439, blue: 0.196, opacity: 1.0)
}