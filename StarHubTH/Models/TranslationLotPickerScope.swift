import Foundation

/// Logique pure du périmètre affiché dans la feuille d'export des lots ZIP.
public enum TranslationLotPickerScope {
    public static func visibleMods(in mods: [ModItem], searchText: String) -> [ModItem] {
        guard !searchText.isEmpty else { return mods }
        return mods.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.folderName.localizedCaseInsensitiveContains(searchText)
        }
    }

    public static func checkedCount(in visibleMods: [ModItem], checked: Set<String>) -> Int {
        visibleMods.lazy.filter { checked.contains($0.folderName) }.count
    }
}
