import SwiftUI
import CoreGraphics

// AppDesignUI.swift
// Design tokens UI pour StarHubFR — côté app (SwiftUI).
// Réexporte Spacing/Radius/Opacity de la couche logique (AppDesignCore,
// testable SPM) et ajoute Font/Color qui nécessitent SwiftUI.
//
// Usage dans les Views :
//   VStack(spacing: AppDesign.Spacing.sm) { ... }
//   .font(AppDesign.Font.body)
//   .cornerRadius(AppDesign.Radius.section)
//   AppDesign.Color.primary.opacity(AppDesign.Opacity.light)
//
// Ce fichier n'est PAS dans le target SPM StarHubTHCore (il importe SwiftUI
// qui n'est pas pertinent pour les tests unitaires logiques).

enum AppDesign {

    // MARK: - Re-export des tokens purs (couche logique)
    typealias Spacing = AppDesignCore.Spacing
    typealias Radius = AppDesignCore.Radius
    typealias Opacity = AppDesignCore.Opacity
    // Ajoutés par le châssis (H-T1). Sans eux, une vue devait écrire
    // `AppDesignCore.Metrics.…` à côté d'`AppDesign.Spacing.…` : deux
    // vocabulaires dans le même fichier, que les lots suivants auraient copiés.
    typealias Grid = AppDesignCore.Grid
    typealias Metrics = AppDesignCore.Metrics
    typealias Shadow = AppDesignCore.Shadow
    typealias Icon = AppDesignCore.Icon

    // MARK: - Typography (SwiftUI.Font)
    // Déduit des tailles réellement utilisées (inventaire spec §1.2) :
    // 74× size 12, 64× size 11, 45× size 13, 30× size 14, etc.
    enum Font {
        // Micro (icônes, chevrons, labels minuscules — 36 occ. pour size 10)
        static let iconXS    = SwiftUI.Font.system(size: 10)
        // Captions / footnotes (64 occ. pour size 11)
        static let footnote  = SwiftUI.Font.system(size: 11)
        // Texte secondaire (74 occ. pour size 12 — le plus utilisé)
        static let caption   = SwiftUI.Font.system(size: 12)
        // Corps standard (45 occ. pour size 13 — StandardRow, corps)
        static let body      = SwiftUI.Font.system(size: 13)
        // Titres de ligne / sidebar (30 occ. pour size 14)
        static let rowTitle  = SwiftUI.Font.system(size: 14)
        // Sous-titres (7 occ. pour size 16)
        static let headline  = SwiftUI.Font.system(size: 16)
        // Titres de vue (utilise déjà .title2/.title3 système)
        static let viewTitle = SwiftUI.Font.system(size: 20, weight: .semibold)

        // Helpers avec weight — évite de répéter .system(size:weight:)
        static func footnote(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 11, weight: w)
        }
        static func caption(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 12, weight: w)
        }
        static func body(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 13, weight: w)
        }
        static func rowTitle(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 14, weight: w)
        }
        static func headline(_ w: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .system(size: 16, weight: w)
        }
    }

    // MARK: - Colors (SwiftUI.Color)
    // Les 3 couleurs système dominantes (94 occurrences combinées dans le code).
    enum Color {
        static let primary    = SwiftUI.Color.primary
        static let secondary  = SwiftUI.Color.secondary
        static let accent     = SwiftUI.Color.accentColor

        // Arrière-plans système (42 occurrences combinées)
        static let windowBg       = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let controlBg      = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let textBg         = SwiftUI.Color(nsColor: .textBackgroundColor)

        // Status (utilisé ponctuellement : HomeView .green, UpdatesView .red, etc.)
        static let success    = SwiftUI.Color.green
        static let warning    = SwiftUI.Color.orange
        static let error      = SwiftUI.Color.red
        static let info       = SwiftUI.Color.blue
    }
}
