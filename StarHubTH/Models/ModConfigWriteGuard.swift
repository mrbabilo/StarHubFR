import Foundation

/// Décide si l'éditeur de configuration peut écrire `config.json`, ou s'il
/// écraserait une écriture faite par quelqu'un d'autre entre-temps.
///
/// **Le fichier est volatile tant que le jeu tourne.** Un mod C# réécrit sa
/// propre configuration quand il veut : UltraSmooth appelle `WriteConfig`
/// depuis quatre sites de son `ModEntry` (migration de version, bascule de
/// profil, commandes console), Modern Config Menu depuis cinq, et la vue
/// « raccourcis » de GMCM en réécrit **N d'un coup** — tous les mods qui
/// déclarent au moins une touche. Relevé en décompilant les cinq mods, voir
/// `docs/audit-mods-config-perf.md`.
///
/// L'éditeur, lui, lisait le fichier à l'ouverture et le réécrivait **en
/// bloc** à l'enregistrement, sans jamais regarder s'il avait bougé. Une
/// session de jeu ouverte à côté suffisait à perdre ce que le mod venait
/// d'écrire — migration comprise.
///
/// **Et le filet ne rattrape pas ce cas.** `backUpCurrentConfig` ne garde
/// qu'une sauvegarde par mod et par jour, et c'est la **première** qui reste
/// (règle voulue : dix réglages changés dans l'après-midi ne doivent pas
/// noyer l'écran des sauvegardes). Éditer à 10 h, laisser le mod réécrire à
/// 14 h, éditer de nouveau à 15 h : la seule copie du jour est celle d'avant
/// 10 h, et l'état de 14 h n'existe plus nulle part. Le contrôle à
/// l'enregistrement n'est donc pas un supplément de prudence — c'est la seule
/// chose qui protège cet état-là.
///
/// La règle ne connaît que le fichier : le jeu qui tourne est un
/// **avertissement** affiché à l'écran, jamais une interdiction. Éditer la
/// config d'un mod en pause pendant une partie ne risque rien, et **379 des
/// 462 mods à `config.json`** du parc de référence sont en pause.
public enum ModConfigWriteGuard {

    /// L'état du fichier au moment d'enregistrer, tel que la relecture l'a
    /// trouvé. `unreadable` est une **troisième** valeur, et non un `nil`
    /// confondu avec `missing` : un fichier illisible n'est pas un fichier
    /// absent, et les traiter pareil ferait passer une panne de lecture pour
    /// un feu vert.
    public enum DiskState: Equatable, Sendable {
        case content(String)
        case missing
        case unreadable
    }

    /// Ce qu'il faut faire de l'enregistrement demandé.
    public enum Decision: Equatable, Sendable {
        /// Écrire : le disque porte ce qu'on avait chargé, ou plus rien, ou
        /// déjà exactement ce qu'on allait écrire.
        case proceed
        /// Le fichier a changé depuis l'ouverture de l'éditeur : demander
        /// avant d'écraser, en disant ce qui est en jeu.
        case externallyChanged
        /// La relecture a échoué : on ne sait pas, et ne pas savoir n'est pas
        /// un consentement.
        case unverifiable
    }

    /// - Parameters:
    ///   - loaded: le contenu lu à l'ouverture de l'éditeur, `nil` si le
    ///     fichier n'existait pas encore.
    ///   - onDisk: ce que la relecture, faite juste avant d'écrire, a trouvé.
    ///   - pending: le texte que l'utilisateur s'apprête à enregistrer.
    ///
    /// La comparaison porte sur le **texte entier**, octet pour octet. Un
    /// simple reformatage compte donc pour une réécriture : le mod *a* touché
    /// au fichier, et ce qu'il a écrit peut porter des champs migrés ou
    /// normalisés. Un faux positif coûte une confirmation ; le manquer coûte
    /// le fichier. C'est aussi pourquoi rien ici ne compare ligne à ligne —
    /// en Swift `"\r\n"` est un seul `Character`, et une comparaison naïve
    /// tiendrait un fichier passé en CRLF pour inchangé.
    public static func decide(loaded: String?,
                              onDisk: DiskState,
                              pending: String) -> Decision {
        switch onDisk {
        case .unreadable:
            return .unverifiable
        case .missing:
            // Plus rien à écraser : que le fichier ait existé à l'ouverture ou
            // non, l'écrire ne détruit rien.
            return .proceed
        case .content(let current):
            if current == loaded { return .proceed }
            // Le disque porte déjà, au caractère près, ce qu'on allait
            // écrire : l'écriture est un non-événement, et demander une
            // confirmation serait une friction pure.
            if current == pending { return .proceed }
            return .externallyChanged
        }
    }

    /// Relit le fichier pour alimenter `decide`.
    ///
    /// **La même lecture que celle de l'ouverture**, `String(contentsOfFile:
    /// encoding: .utf8)` : un fichier qui n'était déjà pas lisible à
    /// l'ouverture ne doit pas devenir « modifié » à l'enregistrement du seul
    /// fait qu'on l'aurait relu autrement.
    public static func readDisk(atPath path: String,
                                fileManager: FileManager = .default) -> DiskState {
        guard fileManager.fileExists(atPath: path) else { return .missing }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .unreadable
        }
        return .content(content)
    }
}
