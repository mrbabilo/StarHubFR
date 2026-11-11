import Foundation

/// Les erreurs qu'UltraSmooth écrit **en TRACE**.
///
/// Depuis la 2.8.0, UltraSmooth rattrape les exceptions de 44 de ses sites
/// (`UltraSmoothLogger.ErrorOnce`) et les écrit une fois par clé et par
/// session, au niveau TRACE, sous la forme
/// `<clé> failed (logged once): <type>: <message>` (décompilé en 2.8.4 —
/// `docs/audit-ultrasmooth-2.8.4.md`). Lues à leur niveau, ces lignes
/// disparaissaient de tout ce qui compte les erreurs : Alertes, historique par
/// mod, badge de la liste, `topErrorMods` — et `LogBudget` les jetait en
/// premier, comme du bruit. Une baisse du compte d'erreurs d'UltraSmooth ne
/// prouvait donc pas qu'il allait mieux.
///
/// La règle les relève au rang d'erreur. Elle est **étroite** à dessein :
/// niveau TRACE, source UltraSmooth, et la formule exacte. Une ligne TRACE
/// ordinaire reste du bruit.
public enum LoggedOnceError {
    static let marker = " failed (logged once): "

    /// Les noms sous lesquels SMAPI écrit la source d'UltraSmooth : le `Name`
    /// de son manifeste (« Ultra Smooth »), et la forme collée par prudence.
    ///
    /// Le garde par nom n'est pas qu'une précision : les deux lecteurs passent
    /// sur tout le journal (239 237 lignes chez l'auteur, ~90 % de TRACE). Une
    /// comparaison de chaînes courtes avant la recherche de la formule évite
    /// une recherche par ligne TRACE — environ 130 ms au lancement, mesurés à
    /// l'échelle de `BenignRule.has`.
    static let sources: Set<String> = ["Ultra Smooth", "UltraSmooth"]

    /// `true` quand une ligne TRACE est en réalité une erreur rattrapée par
    /// UltraSmooth.
    /// - Parameters:
    ///   - rawLevel: le niveau tel qu'écrit dans l'en-tête (`TRACE`, `ERROR`…),
    ///     casse indifférente.
    ///   - source: la source de l'en-tête (le nom du mod), ou `nil`.
    ///   - message: le corps de la ligne, en-tête retiré.
    public static func isError(rawLevel: String, source: String?, message: String) -> Bool {
        guard let source, sources.contains(source),
              rawLevel.caseInsensitiveCompare("TRACE") == .orderedSame else { return false }
        return message.range(of: marker, options: .literal) != nil
    }

    /// `true` pour une entrée déjà lue que cette règle a relevée au rang
    /// d'erreur. L'écran des Journaux le dit (le fichier brut porte TRACE), et
    /// le résumé des lignes dupliquées d'UltraSmooth s'en sert : la ligne
    /// qu'il cite est tronquée à 80 caractères, la formule peut y manquer.
    public static func isPromoted(_ entry: LogEntry) -> Bool {
        guard entry.level == .error, let mod = entry.modName, sources.contains(mod) else { return false }
        return entry.message.range(of: marker, options: .literal) != nil
    }
}
