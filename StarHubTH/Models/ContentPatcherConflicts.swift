import Foundation

/// Un conflit de chargement que **Content Patcher a constaté**, lu dans le
/// journal de SMAPI.
///
/// C'est la source la plus sûre qui existe pour cet axe : ce n'est pas une
/// déduction, c'est Content Patcher qui le dit. Sa contrepartie est qu'elle
/// **constate au lieu de prévenir** — il faut avoir joué avec les deux mods
/// actifs.
///
/// Ce que fait Content Patcher devant deux `Load` exclusifs sur la même cible,
/// vérifié par décompilation IL (`ikdasm`, 2026-08-29) : *« Neither will be
/// applied »* — **aucun des deux**, l'asset reste vanilla. La priorité
/// `Exclusive` est le défaut : `AssetLoadPriority.Exclusive = 0x7FFFFFFF` et
/// `PatchLoader::TryParsePriority` reçoit exactement cette valeur.
///
/// **Limite connue** : un nom de mod contenant le séparateur (« and » ou « , »)
/// rend le découpage impossible. La forme « Multiple » hérite de cette fragilité
/// si un pack se nomme avec une virgule, mais rien n'y remédie sans amener du
/// faux positif.
struct LoadConflict: Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        /// Deux content packs ou plus se disputent la cible.
        case betweenPacks
        /// Un seul pack, dont deux patches se disputent la cible : à signaler à
        /// son auteur, ce n'est pas un arbitrage d'utilisateur.
        case withinOnePack
    }
    let asset: String
    /// Les **noms d'affichage** des packs, tels que Content Patcher les imprime.
    let packs: [String]
    let kind: Kind
}

enum ContentPatcherConflicts {

    /// Le nom sous lequel Content Patcher journalise.
    ///
    /// ⚠️ **`LogSource` ne connaît que `.app` et `.smapi`** : il n'y a pas de
    /// source par mod. C'est `LogEntry.modName` qui porte le nom, extrait du
    /// contexte entre crochets (`[15:55:04 ERROR Content Patcher]`).
    private static let source = "Content Patcher"

    /// Les conflits que le journal rapporte, sans doublon et dans l'ordre de
    /// lecture.
    static func read(from entries: [LogEntry]) -> [LoadConflict] {
        var seen: Set<LoadConflict> = []
        var found: [LoadConflict] = []
        for entry in entries where entry.level == .error && entry.modName == source {
            guard let conflict = parse(entry.message), !seen.contains(conflict) else { continue }
            seen.insert(conflict)
            found.append(conflict)
        }
        return found
    }

    /// **L'ancrage porte sur le préfixe, jamais sur le conseil final**
    /// (`You should remove one…`) : c'est cette fin-là qui changera d'une
    /// version de Content Patcher à l'autre.
    static func parse(_ message: String) -> LoadConflict? {
        if let c = between(message,
                           after: "Two content packs want to load the '",
                           separator: " and ", exactly: 2) { return c }
        if let c = between(message,
                           after: "Multiple content packs want to load the '",
                           separator: ", ") { return c }
        return withinOnePack(message)
    }

    /// `… want to load the '<asset>' asset with the 'Exclusive' priority (<packs>)…`
    private static func between(_ message: String, after prefix: String,
                                separator: String, exactly: Int? = nil) -> LoadConflict? {
        guard message.hasPrefix(prefix) else { return nil }
        let rest = message.dropFirst(prefix.count)
        guard let assetEnd = rest.range(of: "' asset with the 'Exclusive' priority (")
        else { return nil }
        let asset = String(rest[rest.startIndex..<assetEnd.lowerBound])
        let tail = rest[assetEnd.upperBound...]
        guard let close = tail.range(of: ")") else { return nil }
        let packs = String(tail[tail.startIndex..<close.lowerBound])
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        /// Si une arité exacte est attendue, on s'abstient si le découpage n'y correspond pas.
        /// Un nom de pack contenant le séparateur rend impossible de savoir où se fait la
        /// frontière : une paire fausse qui désigne les mauvais mods est pire qu'une paire
        /// tue. Par exemple, le message « Two content packs » dit littéralement deux, et
        /// si `components(separatedBy:)` en rend trois, on ne peut pas savoir duquel
        /// assembler ; on rend `nil` plutôt qu'une fausse attribution.
        if let expected = exactly, packs.count != expected { return nil }
        guard packs.count > 1, !asset.isEmpty else { return nil }
        return LoadConflict(asset: asset, packs: packs, kind: .betweenPacks)
    }

    /// `'<pack>' has multiple patches with the 'Exclusive' priority which load
    /// the '<asset>' asset at the same time (…)`
    private static func withinOnePack(_ message: String) -> LoadConflict? {
        let marker = "' has multiple patches with the 'Exclusive' priority which load the '"
        guard message.hasPrefix("'"), let range = message.range(of: marker) else { return nil }
        let pack = String(message[message.index(after: message.startIndex)..<range.lowerBound])
        let tail = message[range.upperBound...]
        guard let end = tail.range(of: "' asset at the same time") else { return nil }
        let asset = String(tail[tail.startIndex..<end.lowerBound])
        guard !pack.isEmpty, !asset.isEmpty else { return nil }
        return LoadConflict(asset: asset, packs: [pack], kind: .withinOnePack)
    }
}
