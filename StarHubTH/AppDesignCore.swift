import CoreGraphics

// AppDesignCore.swift
// Design tokens centralisés pour StarHubFR — couche logique pure (testable SPM).
// Les valeurs dérivent de l'inventaire du code existant (voir spec §1.2) :
// chaque token correspond à une valeur réellement utilisée dans les Views,
// afin que la migration ne provoque AUCUN diff visuel.
//
// Les tokens Font/Color (qui nécessitent SwiftUI) vivent côté app dans
// StarHubTH/Design/AppDesignUI.swift. Ce fichier ne contient que des
// CGFloat/Double purs pour rester testable sans dépendance UI.

public enum AppDesignCore {

    // MARK: - Spacing (VStack/HStack spacing, padding)
    public enum Spacing {
        /// 4 — micro (badge + texte). ~30 occurrences dans le code.
        public static let xs: CGFloat = 4
        /// 8 — standard interne. Valeur la plus utilisée (35 occ.).
        public static let sm: CGFloat = 8
        /// 12 — entre éléments apparentés (23 occ.).
        public static let md: CGFloat = 12
        /// 16 — entre sections (26 occ.).
        public static let lg: CGFloat = 16
        /// 24 — grosse séparation (HomeView, ModListView).
        public static let xl: CGFloat = 24
        /// 32 — séparation maximale (3 occ.).
        public static let xxl: CGFloat = 32
    }

    // MARK: - Corner radius
    public enum Radius {
        /// 6 — sidebar items, chips. Valeur la plus utilisée (12 occ.).
        public static let sm: CGFloat = 6
        /// 8 — petits éléments (8 occ.).
        public static let md: CGFloat = 8
        /// 10 — `StandardSection` existant (4 occ.).
        public static let section: CGFloat = 10
        /// 12 — cartes, banner, drop zones (5 occ.).
        public static let lg: CGFloat = 12
    }

    // MARK: - Opacity
    public enum Opacity {
        /// 0.05 — arrière-plans très subtils.
        public static let subtle: Double = 0.05
        /// 0.1 — arrière-plans moyens, borders (valeur dominante, 16 occ.).
        public static let light: Double = 0.1
        /// 0.15 — borders accentués, hover (12 occ.).
        public static let medium: Double = 0.15
        /// 0.25 — overlays modaux (4 occ.).
        public static let strong: Double = 0.25
        /// 0.5 — éléments désactivés (14 occ.).
        public static let disabled: Double = 0.5
        /// 0.8 — texte secondaire (14 occ.).
        public static let secondary: Double = 0.8
    }

    // MARK: - Grid (LazyVGrid adaptative)
    /// Ce que la vitrine a codé en dur : une grille qui remplit la largeur
    /// disponible plutôt qu'une bande horizontale qui cache ses éléments.
    public enum Grid {
        /// 240 — largeur minimale d'une carte, `GridItem(.adaptive(minimum:))`.
        public static let minCardWidth: CGFloat = 240
        /// 12 — gouttière, entre colonnes comme entre rangées. Les sections
        /// gardent `Spacing.sm`/`Spacing.lg` pour leur propre respiration.
        public static let gutter: CGFloat = 12
    }

    // MARK: - Metrics (hauteurs et rapports réservés)
    /// « La place est toujours réservée » (spec refonte §2, P4) : ces valeurs
    /// sont ce qui empêche une mise en page de sauter quand une donnée manque.
    public enum Metrics {
        /// 16/9 — la vignette d'un mod, dont la place est tenue même sans image.
        public static let thumbRatio: CGFloat = 16.0 / 9.0
        /// 150 — hauteur du bandeau d'une fiche.
        public static let heroHeight: CGFloat = 150
        /// 560×640 — la feuille de détail ouverte depuis une carte.
        public static let sheetDetailSize = CGSize(width: 560, height: 640)
        /// 18 — hauteur réservée d'une ligne de métadonnées : sans elle, une
        /// carte sans catégorie servie décale toute sa rangée.
        public static let metaRowHeight: CGFloat = 18
    }

    // MARK: - Shadow
    public enum Shadow {
        /// Décolle du fond un contenu posé sur une image — une pastille
        /// blanche sur une vignette claire s'y noierait sans elle.
        ///
        /// Typé explicitement : sans annotation Swift infère `Int`, que
        /// `.shadow(color:radius:y:)` refuse.
        public static let badge: (radius: CGFloat, y: CGFloat) = (3, 1)
    }

    // MARK: - Icon (tailles de glyphe)
    public enum Icon {
        /// 16 — glyphe compact (fermeture d'une fiche).
        public static let sm: CGFloat = 16
        /// 20 — icône d'un état (`StateCard`).
        public static let md: CGFloat = 20
    }
}
