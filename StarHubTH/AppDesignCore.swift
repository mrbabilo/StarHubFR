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
}
