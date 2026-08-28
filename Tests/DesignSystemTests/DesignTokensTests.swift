import Testing
import Foundation
@testable import StarHubTHCore

// DesignTokensTests.swift
// Vérifie que les design tokens ont les valeurs exactes attendues.
// Ces valeurs sont dérivées de l'inventaire du code existant (spec §1.2) :
// chaque token correspond à une valeur réellement utilisée dans les Views,
// afin que la migration ne provoque aucun diff visuel.

struct DesignTokensTests {

    // MARK: - Spacing

    @Test func spacingFollowsExpectedValues() {
        #expect(AppDesignCore.Spacing.xs == 4, "xs must be 4 (micro-espacements)")
        #expect(AppDesignCore.Spacing.sm == 8, "sm must be 8 (standard interne, valeur dominante)")
        #expect(AppDesignCore.Spacing.md == 12, "md must be 12 (entre éléments)")
        #expect(AppDesignCore.Spacing.lg == 16, "lg must be 16 (entre sections)")
        #expect(AppDesignCore.Spacing.xl == 24, "xl must be 24 (grosse séparation)")
        #expect(AppDesignCore.Spacing.xxl == 32, "xxl must be 32 (séparation maximale)")
    }

    @Test func spacingIsMonotonicallyIncreasing() {
        // Les tokens doivent former une échelle croissante pour être prévisibles.
        let values = [
            AppDesignCore.Spacing.xs,
            AppDesignCore.Spacing.sm,
            AppDesignCore.Spacing.md,
            AppDesignCore.Spacing.lg,
            AppDesignCore.Spacing.xl,
            AppDesignCore.Spacing.xxl,
        ]
        for i in 0..<values.count - 1 {
            #expect(values[i] < values[i + 1],
                    "Spacing tokens must be strictly increasing")
        }
    }

    // MARK: - Radius

    @Test func radiusCoversExistingUseCases() {
        // Doit couvrir les valeurs utilisées dans le code (6, 8, 10, 12).
        let allRadii: Set<CGFloat> = [
            AppDesignCore.Radius.sm,
            AppDesignCore.Radius.md,
            AppDesignCore.Radius.section,
            AppDesignCore.Radius.lg,
        ]
        #expect(allRadii.contains(6), "sm must be 6 (sidebar items, chips)")
        #expect(allRadii.contains(8), "md must be 8 (petits éléments)")
        #expect(allRadii.contains(10), "section must be 10 (StandardSection)")
        #expect(allRadii.contains(12), "lg must be 12 (cartes, drop zones)")
    }

    @Test func radiusIsMonotonicallyIncreasing() {
        #expect(AppDesignCore.Radius.sm < AppDesignCore.Radius.md)
        #expect(AppDesignCore.Radius.md < AppDesignCore.Radius.section)
        #expect(AppDesignCore.Radius.section < AppDesignCore.Radius.lg)
    }

    // MARK: - Opacity

    @Test func opacityFollowsExpectedValues() {
        #expect(abs(AppDesignCore.Opacity.subtle - 0.05) < 0.001)
        #expect(abs(AppDesignCore.Opacity.light - 0.1) < 0.001)
        #expect(abs(AppDesignCore.Opacity.medium - 0.15) < 0.001)
        #expect(abs(AppDesignCore.Opacity.strong - 0.25) < 0.001)
        #expect(abs(AppDesignCore.Opacity.disabled - 0.5) < 0.001)
        #expect(abs(AppDesignCore.Opacity.secondary - 0.8) < 0.001)
    }

    @Test func opacityIsMonotonicallyIncreasing() {
        let values = [
            AppDesignCore.Opacity.subtle,
            AppDesignCore.Opacity.light,
            AppDesignCore.Opacity.medium,
            AppDesignCore.Opacity.strong,
            AppDesignCore.Opacity.disabled,
            AppDesignCore.Opacity.secondary,
        ]
        for i in 0..<values.count - 1 {
            #expect(values[i] < values[i + 1],
                    "Opacity tokens must be strictly increasing")
        }
    }

    @Test func opacityRangeIsValid() {
        // Toutes les opacités doivent être dans [0, 1].
        let allOpacities = [
            AppDesignCore.Opacity.subtle,
            AppDesignCore.Opacity.light,
            AppDesignCore.Opacity.medium,
            AppDesignCore.Opacity.strong,
            AppDesignCore.Opacity.disabled,
            AppDesignCore.Opacity.secondary,
        ]
        for op in allOpacities {
            #expect(op > 0, "Opacity must be > 0")
            #expect(op <= 1, "Opacity must be <= 1")
        }
    }

    // MARK: - Grid

    @Test func gridTokensFollowExpectedValues() {
        #expect(AppDesignCore.Grid.minCardWidth == 240,
                "minCardWidth must be 240 (GridItem.adaptive de DiscoverView)")
        #expect(AppDesignCore.Grid.gutter == 12,
                "gutter must be 12 (colonnes et rangées de la grille)")
    }

    // MARK: - Metrics

    @Test func metricsFollowExpectedValues() {
        // Un rapport dérivé ne se compare pas à l'identique : la macro
        // `#expect` a rendu `false` sur deux valeurs qui s'impriment pourtant
        // toutes deux 1.7777777777777777. Une tolérance dit ce qu'on veut
        // vraiment savoir — que le token vaut bien seize neuvièmes.
        let expectedRatio: CGFloat = 16.0 / 9.0
        #expect(abs(AppDesignCore.Metrics.thumbRatio - expectedRatio) < 1e-9,
                "thumbRatio must be 16/9 (vignette de ModCard)")
        #expect(AppDesignCore.Metrics.heroHeight == 150,
                "heroHeight must be 150 (bandeau de la fiche)")
        #expect(AppDesignCore.Metrics.sheetDetailSize == CGSize(width: 560, height: 640),
                "sheetDetailSize must be 560×640 (feuille de détail)")
        #expect(AppDesignCore.Metrics.metaRowHeight == 18,
                "metaRowHeight must be 18 (hauteur réservée de la ligne de méta)")
    }

    // MARK: - Shadow

    @Test func shadowBadgeFollowsExpectedValues() {
        #expect(AppDesignCore.Shadow.badge.radius == 3,
                "badge shadow radius must be 3")
        #expect(AppDesignCore.Shadow.badge.y == 1,
                "badge shadow y offset must be 1")
    }

    // MARK: - Icon

    @Test func iconSizesFollowExpectedValues() {
        #expect(AppDesignCore.Icon.sm == 16, "Icon.sm must be 16 (glyphe compact)")
        #expect(AppDesignCore.Icon.md == 20, "Icon.md must be 20 (icône d'état)")
    }

    @Test func iconSizesAreIncreasing() {
        #expect(AppDesignCore.Icon.sm < AppDesignCore.Icon.md,
                "Icon tokens must form an increasing scale")
    }
}
