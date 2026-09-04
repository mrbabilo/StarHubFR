import Foundation

/// Quelle version de SMAPI est installée, quand deux sources le disent et
/// qu'elles peuvent se contredire.
///
/// **Le marqueur seul ment indéfiniment.** `smapi-internal/.starhubth-installed-version`
/// est écrit par cette app, et par elle seule, à la fin d'une installation
/// réussie — SMAPI ne livre plus rien qui déclare sa propre version de façon
/// fiable (vérifié sur une vraie installation : pas de
/// `smapi-internal/manifest.json`, un `StardewModdingAPI.deps.json` réduit à une
/// coquille, un `runtimeconfig.json` qui ne nomme que la version du runtime
/// .NET). Le jour où l'utilisateur met SMAPI à jour par **son** installateur,
/// rien ne réécrit ce marqueur : l'app annonce éternellement l'ancienne
/// version, et propose une mise à jour déjà faite.
///
/// **La règle : croire la source la plus récente.** Le journal
/// `SMAPI-latest.txt` nomme en première ligne la version réellement *chargée*
/// au dernier lancement. Apparier cette ligne à la **date du fichier** n'est
/// licite que parce que SMAPI le réécrit à chaque lancement — vérifié le
/// 2026-09-04 : une seule bannière dans un fichier de 489 Ko, session du 01/09
/// de 17:39 à 17:44. S'il s'accumulait, la première ligne serait la plus
/// ancienne et la date la plus récente, et la règle préférerait une vieille
/// version à un marqueur juste. S'il a été écrit après le marqueur, une partie a
/// tourné depuis notre installation et c'est lui qui a raison. Sinon, c'est le
/// marqueur : une installation faite par l'app dont le jeu n'a pas encore été
/// relancé est plus récente que tout ce que le journal peut dire.
///
/// **Ce que ça ne rattrape pas**, et c'est assumé : SMAPI installé ailleurs
/// *puis* jeu jamais relancé. Les deux sources parlent alors d'avant, et rien
/// sur le disque ne date l'installation — mesuré le 2026-09-04, la date de
/// `StardewModdingAPI.dll` est celle du **build** de la release (2026-03-14
/// pour 4.5.2), pas celle de la copie, et le dossier `smapi-internal` est
/// retouché par SMAPI lui-même en cours de partie. La fenêtre se referme au
/// premier lancement du jeu — celui-là même pour lequel on met SMAPI à jour.
public enum SmapiVersionEvidence {

    /// Ce qu'une source affirme, et quand elle l'a affirmé.
    public struct Statement: Equatable, Sendable {
        public let version: String
        /// La date d'écriture du fichier d'où vient l'affirmation.
        public let observedAt: Date

        public init(version: String, observedAt: Date) {
            self.version = version
            self.observedAt = observedAt
        }

        /// Vide ou blanche : ce n'est pas une affirmation. Une écriture de
        /// marqueur interrompue ne doit pas faire taire l'autre source.
        var trimmed: String? {
            let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    /// La version à afficher, ou `nil` quand aucune source ne se prononce.
    ///
    /// À date égale, le marqueur l'emporte : il dit ce qui a été **installé**,
    /// quand le journal dit ce qui a été **chargé**.
    public static func resolve(marker: Statement?, log: Statement?) -> String? {
        let markerVersion = marker?.trimmed
        let logVersion = log?.trimmed

        guard let markerVersion else { return logVersion }
        guard let logVersion, let log, let marker else { return markerVersion }

        return log.observedAt > marker.observedAt ? logVersion : markerVersion
    }

    /// La version nommée par la bannière de la première ligne du journal.
    ///
    /// Format réel, relevé sur la machine de référence :
    /// `[17:39:40 INFO  SMAPI] SMAPI 4.5.2 with Stardew Valley 1.6.15 …`
    ///
    /// La forme acceptée ne s'arrête pas à trois segments : SMAPI publie des
    /// `4.0.0.1` et des `4.6.0-beta.3`, et tronquer ferait passer une
    /// pré-version pour la stable du même numéro.
    public static func version(inLogLine line: String) -> String? {
        guard let range = line.range(of: #"SMAPI (\d+(?:\.\d+)+(?:-[0-9A-Za-z.\-]+)?)"#,
                                     options: .regularExpression) else { return nil }
        return String(line[range]).replacingOccurrences(of: "SMAPI ", with: "")
    }
}
