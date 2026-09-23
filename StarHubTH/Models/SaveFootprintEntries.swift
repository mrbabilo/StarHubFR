import Foundation

// Les entrées de la fiche d'une sauvegarde (A1-T6, A1-T9) : les mods en
// pause qui y ont laissé du contenu, et ceux qu'elle a connus et que le
// parc n'a plus. Le scanner et la résolution vivent dans
// `SaveFingerprint.swift`.

/// A1-T6 — ce qu'une sauvegarde porte d'un mod **en pause**, pour la fiche
/// de la sauvegarde : une rangée par mod, qui conduit à sa fiche.
public struct PausedModFootprint: Equatable, Sendable {
    public let folderName: String
    public let name: String
    public let counts: FingerprintCounts

    public init(folderName: String, name: String, counts: FingerprintCounts) {
        self.folderName = folderName
        self.name = name
        self.counts = counts
    }
}

public enum SavePausedFootprints {
    /// Les mods en pause dont la sauvegarde porte des empreintes, les plus
    /// chargés d'abord.
    ///
    /// La résolution reçoit **tous** les UniqueIDs du parc, puis on filtre :
    /// `resolve` attribue au préfixe le plus long *parmi les ids reçus*, et
    /// ne lui donner que les ids en pause ferait retomber l'empreinte d'un
    /// mod actif `A.B_C` sur un `A.B` en pause.
    /// Un id porté par une copie **active** (doublon d'installation, mesuré
    /// sur le parc) ne dort pas : il n'est pas rapporté.
    public static func entries(
        scan: SaveFingerprintScan,
        mods: [ModItem]
    ) -> [PausedModFootprint] {
        let parc = mods.flattenedMods.filter { !$0.uniqueId.isEmpty }
        let resolved = SaveFingerprintResolution.resolve(
            scan, modIDs: Set(parc.map(\.uniqueId)))
        let actifs = Set(parc.filter(\.isEnabled).map(\.uniqueId))
        var vus: Set<String> = []
        var result: [PausedModFootprint] = []
        for mod in parc where !mod.isEnabled && !actifs.contains(mod.uniqueId) {
            guard vus.insert(mod.uniqueId).inserted,
                  let counts = resolved[mod.uniqueId], !counts.isEmpty
            else { continue }
            result.append(PausedModFootprint(
                folderName: mod.folderName, name: mod.name, counts: counts))
        }
        return result.sorted {
            $0.counts.total != $1.counts.total
                ? $0.counts.total > $1.counts.total
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}


/// A1-T9 — un mod que la sauvegarde a connu et que le parc n'a plus.
public struct AbsentModFootprint: Equatable, Sendable {
    /// L'UniqueID tel que SMAPI l'écrit : en minuscules.
    public let uid: String
    public let keys: Int

    public init(uid: String, keys: Int) {
        self.uid = uid
        self.keys = keys
    }
}

public enum SaveAbsentMods {
    /// Les mods **utilisés avec cette partie et plus installés**.
    ///
    /// Source unique : `smapi/mod-data/<uid>/…`, la seule forme qui porte
    /// l'UniqueID exact (SMAPI l'écrit). La tête `<x>/…` ne prouve rien :
    /// mesuré, `foxisadev.bqr/…` est écrit par BetterQuestRewards,
    /// installé. Comparaison sans tenir compte de la casse, sur tout le
    /// parc, packs dépliés et mods en pause compris : un mod en pause n'est
    /// pas désinstallé.
    ///
    /// Un uid cité par `legacy-migrated-<uid>-…` sous un mod **installé** a
    /// été absorbé par ce mod (mesuré : walletautopetter → WalletTools). Le
    /// lister pousserait à réinstaller un mod obsolète.
    public static func entries(
        scan: SaveFingerprintScan,
        mods: [ModItem]
    ) -> [AbsentModFootprint] {
        let entries = absentKeyCounts(scan.modDataKeys, mods: mods).map { (uid, keys) in
            AbsentModFootprint(uid: uid, keys: keys)
        }
        return entries.sorted { (a, b) in
            a.keys != b.keys ? a.keys > b.keys : a.uid < b.uid
        }
    }

    /// La règle elle-même — uid disparu → occurrences —, partagée avec le
    /// nettoyage (A1-T10) : une seule définition de « disparu », pour que
    /// le bouton ne retire jamais autre chose que ce que la section affiche.
    static func absentKeyCounts(
        _ modDataKeys: [String: Int],
        mods: [ModItem]
    ) -> [String: Int] {
        let prefixe = "smapi/mod-data/"
        let marqueur = "legacy-migrated-"
        let parc = Set(mods.allUniqueIds.map { $0.lowercased() })
        var absents: [String: Int] = [:]
        var migrations: [String] = []
        for (cle, occurrences) in modDataKeys where cle.hasPrefix(prefixe) {
            let suite = cle.dropFirst(prefixe.count)
            let proprietaire = suite.prefix { $0 != "/" }.lowercased()
            guard !proprietaire.isEmpty else { continue }
            if parc.contains(proprietaire) {
                let sousCle = suite.drop { $0 != "/" }.dropFirst().lowercased()
                if sousCle.hasPrefix(marqueur) { migrations.append(sousCle) }
            } else {
                absents[proprietaire, default: 0] += occurrences
            }
        }
        return absents.filter { (uid, _) in
            !migrations.contains { $0.hasPrefix(marqueur + uid + "-") }
        }
    }
}
