import Foundation

/// La fusion d'un lot revenu d'un **humain** : chaque entrée est jugée contre
/// l'état courant **complet** du mod — traduit compris — là où
/// `TranslationLotImport.read` n'apparie que les clés encore à traduire.
///
/// Deux traducteurs sur le même mod produisent deux lots identiques à
/// l'export ; le second arrive quand le premier a déjà écrit. La fusion
/// distingue alors ce qui s'écrit sans discussion (clé encore vide) de ce qui
/// demande un arbitrage (les deux ont traduit, différemment) de ce qui ne dit
/// rien (même valeur des deux côtés).
public enum TranslationLotMerge {

    /// Ce que le lot reçu propose pour une clé.
    public enum Disposition: Equatable, Sendable {
        /// Clé encore sans français : la valeur reçue s'écrit direct.
        case writeNow
        /// Les deux côtés ont traduit, différemment : à arbitrer.
        case divergent
        /// Même valeur des deux côtés : rien à faire, comptée.
        case identical
        /// Le traducteur n'a pas rempli sa cible : travail non fait.
        case unfilled
    }

    /// Une entrée reçue et comprise, en attente de décision.
    public struct Proposal: Equatable, Hashable, Sendable {
        public let component: String?
        public let key: String
        /// L'anglais **courant** — c'est lui qui fait foi, jamais la source
        /// que le fichier prétend porter.
        public let source: String
        /// Le français déjà en place, vide pour `.writeNow`.
        public let currentFrench: String
        /// La valeur reçue, relue contre les marques dures de `source`.
        public let incoming: String
        public let disposition: Disposition

        init(component: String?, key: String, source: String,
             currentFrench: String, incoming: String, disposition: Disposition) {
            self.component = component
            self.key = key
            self.source = source
            self.currentFrench = currentFrench
            self.incoming = incoming
            self.disposition = disposition
        }
    }

    /// Le compte rendu d'une fusion : ce qui se propose, et ce qui s'écarte
    /// (mêmes motifs que `TranslationLotImport`).
    public struct Review: Equatable, Sendable {
        public let proposals: [Proposal]
        public let rejections: [TranslationLotImport.Rejection]
    }

    public enum FileRefusal: Error, Equatable, Sendable {
        case unreadable
        case wrongMod
        case wrongLanguage
        /// Aucune clé du fichier ne figure dans l'état courant **complet** :
        /// le lot d'un autre moment, ou d'un autre mod.
        case staleLot
        case unsupportedFormat(Int)
    }

    public static func review(_ data: Data, rows: [TranslationCoverage.DiffRow],
                              mod folderName: String, language: String) throws -> Review {
        guard let lot = TranslationLotImport.decode(data) else { throw FileRefusal.unreadable }
        guard lot.formatVersion == TranslationLot.currentFormatVersion else {
            throw FileRefusal.unsupportedFormat(lot.formatVersion)
        }
        guard lot.mod == folderName else { throw FileRefusal.wrongMod }
        guard lot.language == language else { throw FileRefusal.wrongLanguage }

        // Toutes les rangées, traduites comprises : c'est l'état complet qui
        // fait foi. `writableRows`, elle, ne garde que l'écrivable.
        var current: [String: TranslationCoverage.DiffRow] = [:]
        for row in rows {
            current[TranslationLotImport.identity(row.component, row.key)] = row
        }

        guard lot.entries.contains(where: { current[TranslationLotImport.identity($0.component, $0.key)] != nil })
        else { throw FileRefusal.staleLot }

        var proposals: [Proposal] = []
        var rejections: [TranslationLotImport.Rejection] = []
        // La dernière occurrence d'une identité gagne : c'est la règle de
        // `writableRows` à l'export, la relecture doit résoudre vers la même
        // occurrence que l'écriture.
        var byIdentity: [String: Proposal] = [:]
        var order: [String] = []
        for entry in lot.entries {
            let target = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let row = current[TranslationLotImport.identity(entry.component, entry.key)] else {
                rejections.append(TranslationLotImport.Rejection(
                    component: entry.component, key: entry.key, reason: .unknownKey))
                continue
            }
            guard row.english == entry.source else {
                rejections.append(TranslationLotImport.Rejection(
                    component: entry.component, key: entry.key, reason: .sourceAltered))
                continue
            }
            guard !target.isEmpty else {
                upsert(&byIdentity, &order, entry.component, entry.key, Proposal(
                    component: entry.component, key: entry.key, source: row.english,
                    currentFrench: row.french, incoming: "", disposition: .unfilled))
                continue
            }
            // Mêmes marques dures, dans les deux sens : sans ce gate, une
            // entrée acceptée ici mourrait à l'écriture (`saveTranslation`),
            // comptée nulle part. Même comparaison que la relecture du lot IA.
            let diverging = TranslationTokenCheck
                .mismatches(source: row.english, target: target)
                .filter(\.isHard)
            let missing = diverging.filter { $0.found < $0.expected }.map(\.token)
            guard missing.isEmpty else {
                rejections.append(TranslationLotImport.Rejection(
                    component: entry.component, key: entry.key,
                    reason: .missingHardMarkers(missing)))
                continue
            }
            let extra = diverging.filter { $0.found > $0.expected }.map(\.token)
            guard extra.isEmpty else {
                rejections.append(TranslationLotImport.Rejection(
                    component: entry.component, key: entry.key,
                    reason: .extraHardMarkers(extra)))
                continue
            }
            let existing = row.french.trimmingCharacters(in: .whitespacesAndNewlines)
            let disposition: Disposition = existing.isEmpty
                ? .writeNow
                : (existing == target ? .identical : .divergent)
            upsert(&byIdentity, &order, entry.component, entry.key, Proposal(
                component: entry.component, key: entry.key, source: row.english,
                currentFrench: row.french, incoming: target, disposition: disposition))
        }
        proposals = order.compactMap { byIdentity[$0] }
        return Review(proposals: proposals, rejections: rejections)
    }

    /// Pose une proposition par identité, en remplaçant l'éventuelle
    /// précédente sans bouger sa place : l'ordre du fichier reste l'ordre de
    /// la feuille d'arbitrage.
    private static func upsert(_ byIdentity: inout [String: Proposal],
                               _ order: inout [String],
                               _ component: String?, _ key: String,
                               _ proposal: Proposal) {
        let identity = TranslationLotImport.identity(component, key)
        if byIdentity[identity] == nil { order.append(identity) }
        byIdentity[identity] = proposal
    }
}
