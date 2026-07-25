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
}
