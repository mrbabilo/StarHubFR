import Foundation

/// Les contrôles **réels** du joueur, lus dans les options que le jeu a
/// écrites — pas les valeurs par défaut de `GameControlDefaults`.
///
/// Relevé dans `Stardew Valley.dll` (2026-10-03) : en solo, une partie
/// chargée pose `Game1.options = loaded.options` puis
/// `SaveDefaultOptions()` les écrit dans `default_options` — c'est donc le
/// fichier des contrôles de la dernière partie jouée, remaps de Global
/// Config Settings Rewrite compris (il réécrit `Game1.options` au
/// chargement). `startup_preferences` porte un `<clientOptions>`, qui ne
/// sert qu'au joueur invité d'une partie à plusieurs (`saveClientOptions`) :
/// il ne vient qu'en secours.
///
/// Forme d'un contrôle : `<moveUpButton><InputButton><key>Z</key>
/// <mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton>
/// </moveUpButton>`. `key` est un nom `Keys` de XNA, qui est aussi le nom
/// `SButton` de la touche ; `None` ne lie rien.
public enum GameControlPreferences {

    public enum Source: String, Sendable {
        /// Valeurs par défaut du jeu : aucun fichier lisible.
        case defaults
        /// `default_options` : les contrôles de la dernière partie jouée.
        case lastGame
        /// `startup_preferences` (`clientOptions`) : secours.
        case startupPreferences
    }

    /// Les contrôles d'un fichier d'options, dans l'ordre et sous les noms
    /// de `GameControlDefaults` ; un contrôle absent du fichier garde sa
    /// valeur par défaut. `nil` si le XML ne porte aucun contrôle connu.
    public static func controls(fromXML data: Data) -> [GameControlDefaults.GameControl]? {
        let reader = Reader(names: Set(GameControlDefaults.controls.map(\.name)))
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), !reader.found.isEmpty else { return nil }
        return GameControlDefaults.controls.map { control in
            reader.found[control.name].map { .init(name: control.name, buttons: $0) } ?? control
        }
    }

    /// Le dossier de données du jeu sur macOS.
    public static var appDataFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/StardewValley")
    }

    /// `default_options`, puis `startup_preferences`, puis les défauts.
    public static func load(appDataFolder: URL) -> (controls: [GameControlDefaults.GameControl], source: Source) {
        for (file, source) in [("default_options", Source.lastGame),
                               ("startup_preferences", .startupPreferences)] {
            if let data = FileManager.default.contents(atPath: appDataFolder.appendingPathComponent(file).path),
               let controls = controls(fromXML: data) {
                return (controls, source)
            }
        }
        return (GameControlDefaults.controls, .defaults)
    }

    /// Lecteur SAX : le premier élément de chaque contrôle connu, ses
    /// `InputButton` réduits en noms de bouton.
    private final class Reader: NSObject, XMLParserDelegate {
        let names: Set<String>
        var found: [String: [String]] = [:]
        private var current: String?
        private var buttons: [String] = []
        private var text = ""

        init(names: Set<String>) { self.names = names }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            if current == nil, names.contains(element), found[element] == nil {
                current = element
                buttons = []
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                    qualifiedName: String?) {
            defer { text = "" }
            guard let control = current else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "key" where !value.isEmpty && value != "None":
                buttons.append(value)
            case "mouseLeft" where value == "true":
                buttons.append("MouseLeft")
            case "mouseRight" where value == "true":
                buttons.append("MouseRight")
            case control:
                var unique: [String] = []
                for button in buttons where !unique.contains(button) { unique.append(button) }
                found[control] = unique
                current = nil
            default:
                break
            }
        }
    }
}

extension GameControlPreferences.Source {
    /// La réserve qui dit contre quels contrôles le rapport a jugé.
    var caveatKey: String {
        switch self {
        case .defaults: L10n.Keybinds.gameCaveat
        case .lastGame: L10n.Keybinds.gameCaveatLastGame
        case .startupPreferences: L10n.Keybinds.gameCaveatStartup
        }
    }
}
