import Foundation

/// L'inverse de ce que fait la lecture : d'un **libellé** de composant,
/// retrouver son **dossier**.
///
/// La vue diff étiquette ses lignes par composant
/// (`TranslationCoverage.componentLabel`), parce qu'un mod peut porter
/// plusieurs dossiers `i18n` — un pack en a un par composant, et deux
/// composants peuvent définir la même clé. Pour écrire, il faut refaire ce
/// chemin en sens inverse : se tromper poserait la traduction d'un composant
/// dans le fichier d'un autre, où elle ne serait jamais chargée, et où elle
/// écraserait peut-être une clé homonyme.
public enum TranslationComponentResolver {

    /// Le dossier `i18n` d'où vient une ligne du diff.
    ///
    /// - Parameter component: `DiffRow.component` — `nil` quand le mod n'a
    ///   qu'un seul dossier `i18n`, le cas courant.
    /// - Returns: `nil` si le libellé ne correspond à aucun composant, ou si
    ///   l'absence de libellé reste ambiguë. Ne rien écrire vaut mieux
    ///   qu'écrire dans un composant choisi au hasard.
    public static func directory(forComponent component: String?,
                                 inModDirectory modDirectory: URL,
                                 fileManager: FileManager = .default) -> URL? {
        let directories = I18nLocaleResolver.i18nDirectories(inModDirectory: modDirectory,
                                                             fileManager: fileManager)
        guard let component else {
            // `nil` ne veut dire « le seul dossier » que s'il n'y en a bien
            // qu'un. Sur un pack, c'est une question sans réponse — pas une
            // invitation à prendre le premier venu.
            return directories.count == 1 ? directories.first : nil
        }
        return directories.first {
            TranslationCoverage.componentLabel(of: $0, under: modDirectory) == component
        }
    }
}
