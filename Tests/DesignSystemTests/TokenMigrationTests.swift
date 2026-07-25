import Testing
import Foundation
@testable import StarHubTHCore

// TokenMigrationTests.swift
// Vérifie que les tokens correspondent à des valeurs réellement utilisées
// dans le code avant migration. Ce test protège contre l'introduction
// accidentelle d'une nouvelle valeur jamais testée visuellement : si un
// token ne correspond à aucune valeur historique, le build casse et force
// une vérification visuelle manuelle.
//
// Les "known-good values" proviennent du grep §1.2 de la spec (inventaire
// du code au commit a3937f6).

struct TokenMigrationTests {

    /// Toutes les valeurs numériques qui étaient utilisées ad-hoc dans le code
    /// avant la migration vers les tokens. Toute nouvelle valeur tokenisée
    /// doit appartenir à cet ensemble (ou être explicitement justifiée).
    private static let knownGoodValues: Set<CGFloat> = [
        // Spacings observés (spacing: N et .padding(N))
        2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 24, 28, 30, 32, 40,
        // Corner radii observés (6, 8, 10, 12 déjà ci-dessus)
        // Font sizes observées
        9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24,
        // Grandes icônes empty-state
        40, 44, 48, 56,
    ]

    @Test func allSpacingTokensArePreviouslyUsedValues() {
        let tokenSpacings: [CGFloat] = [
            AppDesignCore.Spacing.xs,
            AppDesignCore.Spacing.sm,
            AppDesignCore.Spacing.md,
            AppDesignCore.Spacing.lg,
            AppDesignCore.Spacing.xl,
            AppDesignCore.Spacing.xxl,
        ]
        for value in tokenSpacings {
            #expect(Self.knownGoodValues.contains(value),
                    "Spacing token \(value) n'est pas une valeur éprouvée — vérifier visuellement")
        }
    }

    @Test func allRadiusTokensArePreviouslyUsedValues() {
        let tokenRadii: [CGFloat] = [
            AppDesignCore.Radius.sm,
            AppDesignCore.Radius.md,
            AppDesignCore.Radius.section,
            AppDesignCore.Radius.lg,
        ]
        for value in tokenRadii {
            #expect(Self.knownGoodValues.contains(value),
                    "Radius token \(value) n'est pas une valeur éprouvée — vérifier visuellement")
        }
    }

    @Test func allOpacityTokensArePreviouslyUsedValues() {
        // Opacités observées dans le code : 0.03, 0.04, 0.05, 0.06, 0.08, 0.1,
        // 0.12, 0.15, 0.2, 0.25, 0.5, 0.6, 0.7, 0.8.
        // Les tokens retenus (0.05, 0.1, 0.15, 0.25, 0.5, 0.8) sont tous
        // dans cet ensemble.
        let knownOpacities: Set<Double> = [
            0.03, 0.04, 0.05, 0.06, 0.08, 0.1, 0.12, 0.15, 0.2, 0.25, 0.5, 0.6, 0.7, 0.8, 0.85,
        ]
        let tokenOpacities = [
            AppDesignCore.Opacity.subtle,
            AppDesignCore.Opacity.light,
            AppDesignCore.Opacity.medium,
            AppDesignCore.Opacity.strong,
            AppDesignCore.Opacity.disabled,
            AppDesignCore.Opacity.secondary,
        ]
        for value in tokenOpacities {
            #expect(knownOpacities.contains(value),
                    "Opacity token \(value) n'est pas une valeur éprouvée — vérifier visuellement")
        }
    }
}
