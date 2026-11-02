import Foundation

extension GmcmModOptions {
    /// Les groupes de l'éditeur dans l'ordre du menu en jeu (GMCM ou
    /// ModernConfigMenu) : une section vient au rang de sa première option,
    /// et ses rangées dans l'ordre du menu. Ce que le menu ne montre pas garde
    /// l'ordre du fichier, après ; le groupe sans section reste en dernier.
    /// Sans capture, rien ne bouge.
    public static func arranged(_ groups: [ConfigEditorModel.Group],
                                by gmcm: GmcmModOptions?) -> [ConfigEditorModel.Group] {
        guard let gmcm else { return groups }
        func rank(_ row: ConfigEditorModel.Row) -> Int { gmcm.entry(for: row.keyPath)?.order ?? .max }
        let sorted = groups.map { group in
            ConfigEditorModel.Group(section: group.section, rows: group.rows.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map(\.element))
        }
        let sectioned = sorted.enumerated().filter { $0.element.section != nil }
            .sorted { (sorted[$0.offset].rows.map(rank).min() ?? .max, $0.offset)
                    < (sorted[$1.offset].rows.map(rank).min() ?? .max, $1.offset) }
            .map(\.element)
        return sectioned + sorted.filter { $0.section == nil }
    }
}
