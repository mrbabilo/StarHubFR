import Foundation

/// Une règle de reconnaissance : à quoi reconnaît-on un fichier déposé, et où
/// doit-il aller.
public struct DroppedContentRule: Equatable, Sendable {
    /// Les clés que le fichier doit **toutes** porter. C'est un sous-ensemble
    /// requis, pas une égalité : un auteur peut ajouter un champ sans que le
    /// fichier cesse d'être ce qu'il est.
    public let requiredKeys: Set<String>
    /// Le mod hôte, par son `UniqueID` SMAPI.
    public let hostUniqueId: String
    /// Le sous-dossier de destination, relatif au dossier du mod hôte.
    public let destinationSubpath: String
    /// Le nom affiché à l'utilisateur dans les messages.
    public let hostDisplayName: String
}

/// Ce qu'on peut faire d'un fichier reconnu.
public enum DroppedContentDestination: Equatable, Sendable {
    /// Le chemin exact où écrire. `hostIsPaused` sert à le dire à
    /// l'utilisateur : le fichier ne prendra effet qu'à la réactivation.
    case ready(URL, hostIsPaused: Bool)
    /// Le mod hôte n'est pas installé. On le nomme plutôt que de créer son
    /// dossier — un dossier sans `manifest.json` serait un faux mod de plus.
    case hostMissing(hostDisplayName: String)
    /// Le nom de fichier de l'archive n'est pas utilisable tel quel.
    case unusableFileName
}

/// Reconnaît les téléchargements qui ne sont pas des mods mais du **contenu
/// destiné au dossier d'un autre mod**.
///
/// Ces fichiers n'ont pas de `manifest.json` : SMAPI ne les chargerait pas s'ils
/// étaient posés dans `Mods/`. Les refuser comme mods est juste ; laisser
/// l'utilisateur sans destination ne l'est pas. Cas d'origine :
/// `Cloth And Colors Bag` (Nexus 50108), 1,4 Ko, un unique JSON de sac ItemBags.
///
/// **La reconnaissance porte sur la signature de clés, jamais sur un identifiant
/// contenu dans le fichier.** Le `ModUniqueId` d'un sac ItemBags désigne le mod
/// dont il stocke les objets — `selph.textileexpansion` pour celui-ci — et non
/// sa destination. Les échantillons officiels le confirment
/// (`Aquilegia.SweetTooth.json`, `Hadi.JASoda.json` : des mods sources). Router
/// sur ce champ écrirait dans un dossier qui n'est pas la cible, et qui souvent
/// n'existe pas.
///
/// Mesuré sur les 951 mods du parc de référence : 9 mods livrent un dossier
/// d'exemples, mais 8 sont des gabarits de *content pack* (avec manifeste).
/// ItemBags est le seul à attendre un fichier nu — d'où une table à une entrée,
/// faite pour que la suivante soit une ligne de données.
public enum DroppedContentRecognizer {
    public static let rules: [DroppedContentRule] = [
        DroppedContentRule(
            // Relevé sur les échantillons livrés par ItemBags dans
            // `assets/Modded Bags/Samples (Copy into Modded Bags folder to use)/`.
            requiredKeys: ["BagId", "BagName", "Prices", "Capacities", "SizeSellers"],
            hostUniqueId: "SlayerDharok.Item_Bags",
            destinationSubpath: "assets/Modded Bags",
            hostDisplayName: "ItemBags"
        )
    ]

    /// La règle qui reconnaît ce contenu, ou `nil`.
    public static func rule(forJSONKeys keys: Set<String>) -> DroppedContentRule? {
        rules.first { $0.requiredKeys.isSubset(of: keys) }
    }

    /// Le nom de fichier réduit à un composant sûr, ou `nil` s'il ne l'est pas.
    ///
    /// **Refuser plutôt qu'assainir.** Une archive qui contient `../../evil.json`
    /// ne fait pas une coquille : la corriger en silence pour elle reviendrait à
    /// accepter la tentative. C'est le défaut relevé lors de l'audit de la
    /// chaîne d'archives de Stardrop, et il n'a pas à entrer ici.
    public static func safeFileName(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("."),
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".", trimmed != ".."
        else { return nil }
        return trimmed
    }

    /// Où écrire ce fichier, compte tenu des mods installés.
    ///
    /// Le dossier retenu est celui du mod hôte **tel qu'il est sur le disque** :
    /// préfixé d'un point s'il est en pause, conformément à la convention du
    /// fork (cf. `docs/DOMAINE.md`). Écrire dans le nom non préfixé créerait un
    /// dossier fantôme à côté du vrai.
    public static func destination(for rule: DroppedContentRule,
                                   fileName: String,
                                   installedMods: [ModItem],
                                   gameDir: String) -> DroppedContentDestination {
        guard let safeName = safeFileName(from: fileName) else { return .unusableFileName }

        let wanted = rule.hostUniqueId.lowercased()
        guard let host = allMods(in: installedMods).first(where: {
            $0.uniqueId.lowercased() == wanted
        }) else {
            return .hostMissing(hostDisplayName: rule.hostDisplayName)
        }

        let physicalFolder = host.isEnabled ? host.folderName : "." + host.folderName
        let hostRoot = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods")
            .appendingPathComponent(physicalFolder)
        let url = hostRoot
            .appendingPathComponent(rule.destinationSubpath)
            .appendingPathComponent(safeName)

        // Défense en profondeur : le nom du fichier est déjà filtré, mais le
        // sous-dossier vient de la table de règles. Vérifier le chemin **après**
        // construction ferme la porte à une règle mal écrite, sans coût.
        guard url.standardizedFileURL.path
                .hasPrefix(hostRoot.standardizedFileURL.path + "/") else {
            return .unusableFileName
        }
        return .ready(url, hostIsPaused: !host.isEnabled)
    }

    /// Écrit le fichier reconnu à sa destination, en créant les dossiers
    /// manquants — un hôte fraîchement installé peut ne pas avoir encore son
    /// sous-dossier de contenu.
    ///
    /// La sauvegarde de l'hôte avant écrasement appartient à l'appelant : c'est
    /// une décision d'orchestration, et `ModInstallBackupManager` la porte déjà
    /// pour toute installation par-dessus un mod existant.
    public static func install(from source: URL, to destination: URL,
                               fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    /// Le premier fichier JSON d'une archive extraite qu'une règle reconnaît.
    ///
    /// N'examine que la **racine** : ces fichiers se distribuent seuls ou à
    /// quelques-uns, jamais enfouis. Descendre plus bas ferait courir le risque
    /// d'attraper un fichier interne d'un mod légitime dont le manifeste n'a pas
    /// été détecté pour une autre raison.
    public static func recognize(inExtractedDirectory directory: URL,
                                 fileManager: FileManager = .default)
        -> (rule: DroppedContentRule, fileURL: URL)? {
        // `try?` délibéré : un dossier illisible n'a simplement rien à
        // reconnaître, et l'appelant ne pourrait qu'afficher le refus ordinaire.
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension.lowercased() == "json" {
            // Lecture **laxiste** : ces fichiers sont écrits à la main par les
            // mêmes auteurs que les i18n et portent les mêmes tolérances. Le
            // sac qui a motivé cette fonctionnalité contient un
            // `//Special Items` que `JSONSerialization` refuse — s'en tenir à
            // lui rendait le reconnaisseur aveugle au cas même qui l'a fait
            // naître.
            guard let data = fileManager.contents(atPath: url.path),
                  let decoded = I18nFileDecoder.decode(data),
                  let object = I18nLenientParser.lenientObject(decoded.text),
                  let match = rule(forJSONKeys: Set(object.keys))
            else { continue }
            return (match, url)
        }
        return nil
    }

    /// Les mods et les composants des packs : un framework hôte peut très bien
    /// être livré à l'intérieur d'un dossier multi-composants.
    private static func allMods(in mods: [ModItem]) -> [ModItem] {
        mods.flatMap { mod -> [ModItem] in
            guard mod.isGroup, let children = mod.children else { return [mod] }
            return children
        }
    }
}
