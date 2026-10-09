import Foundation

/// Le rapport persistant de réparation — sorti de `ModFolderRepairer.swift`,
/// verrouillé en taille par le cliquet des conventions.
extension ModFolderRepairer {
    /// Le rapport persistant de la réparation, posé **dans** son `_Trash_` :
    /// le rapport en mémoire meurt au relancement, et avec lui la raison de
    /// chaque mise en quarantaine. Nom pointé, exclu des entrées listées et
    /// comptées ; « Vider » l'emporte avec la quarantaine.
    public static let reportFileName = ".starhubfr-repair-report.json"

    /// Écrit les éléments **réellement déplacés** dans le rapport du `_Trash_`.
    /// Deux réparations dans la même seconde partagent le dossier : on fusionne.
    /// Un rapport existant illisible n'est jamais écrasé — il porte peut-être
    /// des raisons qu'on ne sait plus relire. Un échec d'écriture n'interrompt
    /// pas la réparation : le rapport est un constat, pas une opération.
    static func persistReport(_ items: [Item], in trashDir: String, fm: FileManager) {
        let url = URL(fileURLWithPath: (trashDir as NSString).appendingPathComponent(Self.reportFileName))
        var all = items
        if fm.fileExists(atPath: url.path) {
            do {
                all = try JSONDecoder().decode([Item].self, from: Data(contentsOf: url)) + items
            } catch {
                return
            }
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(all).write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}
