import Foundation

/// A5-T6 — les dépendances qu'un mod C# ne déclare pas : il cite **par son
/// nom** un type interne d'un autre mod (`AccessTools.TypeByName`,
/// `Assembly.GetType`, `Type.GetType`, `FullName ==`…). Quand l'autre mod
/// renomme ce type à une mise à jour, la recherche rend `null` et le citant
/// perd une fonction, le plus souvent sans rien journaliser.
///
/// Règle **mesurée** sur le parc le 2026-10-08 (ROADMAP, A5-T6) : un
/// littéral du tas `#US` compte s'il est le nom complet d'un `TypeDef` de
/// l'`EntryDll` d'**un seul** autre mod, et que le citant ne le définit pas
/// lui-même. L'heuristique d'origine (« racine du nom = nom de DLL ») se
/// trompait dans les deux sens : 118 chaînes qu'aucun type ne confirme
/// (identifiants d'objets, clés `modData`), 95 vraies références manquées
/// (`Pathoschild.Stardew.*`). Relu dans le C# décompilé, un cas par cible :
/// aucun faux positif.
public enum HiddenCodeDependencies {

    public struct Assembly: Equatable, Sendable {
        public let uniqueId: String
        public let definedTypes: Set<String>
        public let citedNames: Set<String>

        public init(uniqueId: String, definedTypes: Set<String>, citedNames: Set<String>) {
            self.uniqueId = uniqueId
            self.definedTypes = definedTypes
            self.citedNames = citedNames
        }
    }

    /// `citing` lit le code interne de `target` ; `typeNames` triés.
    public struct Link: Hashable, Sendable {
        public let citing: String
        public let target: String
        public let typeNames: [String]

        public init(citing: String, target: String, typeNames: [String]) {
            self.citing = citing
            self.target = target
            self.typeNames = typeNames
        }
    }

    /// Ce qu'une `EntryDll` définit et cite. `nil` hors assembly CLI lisible.
    public static func assembly(uniqueId: String, bytes: [UInt8]) -> Assembly? {
        guard let root = DotNetMetadata.metadataRootOffset(inPE: bytes),
              let file = DotNetMetadata.MetadataFile(bytes: bytes, root: root) else { return nil }
        return Assembly(uniqueId: uniqueId, definedTypes: file.typeDefFullNames(),
                        citedNames: Set(file.userStrings().compactMap(citedName)))
    }

    /// Le nom de type qu'un littéral désigne, ou `nil` s'il n'en a pas la
    /// forme. Coupé avant `,` (nom d'assembly : `"T, Asm"`) et `:` (méthode :
    /// `AccessTools.Method("T:M")`) ; au moins un espace de noms.
    static func citedName(_ literal: String) -> String? {
        var head = Substring(literal)
        if let comma = head.firstIndex(of: ",") { head = head[..<comma] }
        if let colon = head.firstIndex(of: ":") { head = head[..<colon] }
        let name = head.trimmingCharacters(in: .whitespaces)
        guard name.count <= 512 else { return nil }
        let nesting = name.split(separator: "+", omittingEmptySubsequences: false)
        let segments = nesting[0].split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments.allSatisfy(isIdentifier), nesting.allSatisfy(isIdentifier),
              let first = segments[0].first, first.isLetter || first == "_" else { return nil }
        return name
    }

    private static func isIdentifier<S: StringProtocol>(_ part: S) -> Bool {
        !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || "_`<>.".contains($0) }
    }

    /// Les liens citant → cible, triés. Un même mod installé deux fois reste
    /// un seul propriétaire (`UniqueID` sans casse) ; un nom défini par
    /// plusieurs mods est du code source partagé, il ne désigne personne.
    public static func links(_ assemblies: [Assembly]) -> [Link] {
        var owners: [String: Set<String>] = [:]
        var display: [String: String] = [:]
        for assembly in assemblies where !assembly.uniqueId.isEmpty {
            let key = assembly.uniqueId.lowercased()
            if display[key] == nil { display[key] = assembly.uniqueId }
            for type in assembly.definedTypes { owners[type, default: []].insert(key) }
        }
        var grouped: [String: [String: Set<String>]] = [:]
        for assembly in assemblies where !assembly.uniqueId.isEmpty {
            let citing = assembly.uniqueId.lowercased()
            for name in assembly.citedNames where !assembly.definedTypes.contains(name) {
                guard var owning = owners[name] else { continue }
                owning.remove(citing)
                guard owning.count == 1, let target = owning.first else { continue }
                grouped[citing, default: [:]][target, default: []].insert(name)
            }
        }
        return grouped.flatMap { citing, targets in
            targets.map { target, names in
                Link(citing: display[citing] ?? citing, target: display[target] ?? target,
                     typeNames: names.sorted())
            }
        }.sorted {
            ($0.citing.lowercased(), $0.target.lowercased()) < ($1.citing.lowercased(), $1.target.lowercased())
        }
    }

    /// Les liens que le manifeste du citant tait. `declared` rend les
    /// `UniqueID` de ses `Dependencies` (requises ou optionnelles).
    public static func undeclared(_ links: [Link], declared: (String) -> [String]) -> [Link] {
        links.filter { link in
            !declared(link.citing).contains { $0.caseInsensitiveCompare(link.target) == .orderedSame }
        }
    }
}

extension DotNetMetadata.MetadataFile {

    /// Les littéraux du tas `#US` (§II.24.2.4), dans l'ordre : longueur
    /// compressée, UTF-16 LE, un octet de drapeau. Une entrée tronquée
    /// arrête la lecture — jamais un demi-littéral.
    func userStrings() -> [String] {
        guard let heap = userStringHeap else { return [] }
        var out: [String] = []
        var position = heap.lowerBound
        while position < heap.upperBound {
            guard let length = DotNetMetadata.compressedUInt(bytes, &position) else { break }
            guard length > 0 else { continue }
            guard position + length <= heap.upperBound else { break }
            let units = stride(from: position, to: position + length - 1, by: 2).compactMap {
                DotNetMetadata.u16(bytes, $0)
            }
            out.append(String(decoding: units, as: UTF16.self))
            position += length
        }
        return out
    }

    /// Les noms complets des `TypeDef`, à la façon de la réflexion :
    /// `Espace.Type`, `Espace.Externe+Interne` (table `NestedClass`).
    func typeDefFullNames() -> Set<String> {
        let typeCount = rowCount[0x02] ?? 0
        guard typeCount > 0 else { return [] }
        let nameWidth = widths.string
        var enclosing: [Int: Int] = [:]
        let typeIndex = widths.simple(0x02)
        for row in stride(from: 1, through: rowCount[0x29] ?? 0, by: 1) {
            if let nested = column(table: 0x29, row: row, at: 0, width: typeIndex),
               let outer = column(table: 0x29, row: row, at: typeIndex, width: typeIndex) {
                enclosing[nested] = outer
            }
        }
        func fullName(_ row: Int, depth: Int) -> String? {
            guard let nameIndex = column(table: 0x02, row: row, at: 4, width: nameWidth),
                  let name = string(at: nameIndex) else { return nil }
            if let outer = enclosing[row], depth < 16 {
                return fullName(outer, depth: depth + 1).map { $0 + "+" + name }
            }
            guard let spaceIndex = column(table: 0x02, row: row, at: 4 + nameWidth, width: nameWidth),
                  let space = string(at: spaceIndex) else { return nil }
            return space.isEmpty ? name : space + "." + name
        }
        return Set((1...typeCount).compactMap { fullName($0, depth: 0) })
    }
}
