import Foundation

/// Les choix que les mods C# déclarent **par leurs types** — l'extraction
/// hors jeu de ce que MCM voit en jeu (C4-T11). Un mod ne publie pas ses
/// valeurs autorisées dans `config.json` : elles vivent dans la DLL, dans
/// le type de sa propriété (`PlacementRule` → Strict/Loose/Anarchy).
/// `tools/gmcm_options.py` fige ce que le parc en montre dans
/// `assets/gmcm-options.json` ; ce type le décode et répond au lookup.
///
/// Le repli assumé : un mod absent du dataset reste en champ texte —
/// l'extraction ne connaît que les propriétés à enum **de l'assembly** ;
/// les listes passées en littéraux à l'API GMCM et les bornes min/max des
/// nombres restent à prendre (voir ROADMAP).
public struct GmcmOptions: Equatable, Sendable {
    /// UniqueID en bas de casse → clé de config → valeurs dans l'ordre de
    /// déclaration de l'enum.
    private let byUid: [String: [String: [String]]]

    public init?(data: Data) {
        let raw: [String: [String: [String]]]
        do {
            raw = try JSONDecoder().decode([String: [String: [String]]].self, from: data)
        } catch {
            // Le patron des stores Core (ModUpdateSnoozer) : l'échec de
            // décodage se dit, il n'avale pas sa cause.
            print("Warning: gmcm-options dataset undecodable: \(error)")
            return nil
        }
        byUid = Dictionary(uniqueKeysWithValues: raw.map { ($0.key.lowercased(), $0.value) })
    }

    /// Les valeurs d'une clé, `nil` hors dataset. Les deux côtés du lookup
    /// sont insensibles à la casse : SMAPI normalise l'UniqueID, et les clés
    /// de config reprennent le nom de la propriété C# à la casse d'usage.
    public func values(forKey key: String, ofMod uniqueId: String) -> [String]? {
        byUid[uniqueId.lowercased()]?.values(forKey: key)
    }
}

private extension Dictionary where Key == String, Value == [String] {
    /// Exact d'abord, puis sans la casse — la clé du fichier est presque
    /// toujours l'orthographe de la propriété, le second passage couvre
    /// les rares écarts.
    func values(forKey key: String) -> [String]? {
        if let exact = self[key] { return exact }
        let lowered = key.lowercased()
        return first { $0.key.lowercased() == lowered }?.value
    }
}

public extension GmcmOptions {
    /// Le dict des clés à choix pour un mod, prêt pour `ConfigEditorModel
    /// .groups(gmcmChoices:)`. Le dataset vit en ressource de bundle, figé
    /// du parc par `tools/gmcm_options.py` — le même patron que
    /// `SButtonTable` : relevé rejouable, jamais une analyse à chaque
    /// ouverture.
    static let bundled: GmcmOptions? = {
        guard let url = Bundle.main.url(forResource: "gmcm-options", withExtension: "json") else {
            return nil
        }
        do {
            return GmcmOptions(data: try Data(contentsOf: url))
        } catch {
            print("Warning: gmcm-options dataset unreadable: \(error)")
            return nil
        }
    }()

    /// Toutes les clés à choix d'un mod, `[:]` hors dataset.
    func options(forMod uniqueId: String) -> [String: [String]] {
        byUid[uniqueId.lowercased()] ?? [:]
    }
}
