import Foundation

/// Le sous-ensemble d'ECMA-335 que la lecture des choix de config exige
/// (**C4-T11 suite**) : de quoi atteindre `PropertyMap`, `Property`,
/// `TypeDef` et `Field` dans une DLL de mod, et rien de plus. **Aucun
/// corps de méthode n'est décodé** — les listes passées en littéraux à
/// l'API GMCM et les bornes min/max des nombres demandent l'IL, elles
/// restent hors de portée (ROADMAP).
///
/// Ce qui est implémenté l'a été sur **mesure du parc** (455 DLL,
/// 2026-09-15), pas sur lecture de la spec seule : les deux largeurs
/// d'index de heap existent vraiment (26 DLL en 4 octets), les tables
/// d'indirection n'existent nulle part mais sont **détectées** plutôt
/// qu'ignorées, et le stream non compressé `#-` est absent du parc.
public enum DotNetMetadata {

    // MARK: - Entiers compressés (§II.23.2)

    /// Décode l'entier compressé à `position`, qu'il avance. `nil` sur un
    /// tampon tronqué — jamais une valeur inventée.
    public static func compressedUInt(_ bytes: [UInt8], _ position: inout Int) -> Int? {
        guard position < bytes.count else { return nil }
        let first = bytes[position]
        if first & 0x80 == 0 {
            position += 1
            return Int(first)
        }
        if first & 0xC0 == 0x80 {
            guard position + 2 <= bytes.count else { return nil }
            let value = (Int(first & 0x3F) << 8) | Int(bytes[position + 1])
            position += 2
            return value
        }
        guard first & 0xE0 == 0xC0, position + 4 <= bytes.count else { return nil }
        let value = (Int(first & 0x1F) << 24) | (Int(bytes[position + 1]) << 16)
            | (Int(bytes[position + 2]) << 8) | Int(bytes[position + 3])
        position += 4
        return value
    }

    // MARK: - Largeur des colonnes (§II.24.2.6)

    /// Les familles d'index codés dont ce lecteur a besoin pour **mesurer**
    /// les lignes des tables qui précèdent celles qu'il lit : une table ne
    /// se localise qu'en additionnant la taille de toutes les précédentes.
    public enum CodedIndex {
        case typeDefOrRef, hasConstant, hasCustomAttribute, hasFieldMarshal
        case hasDeclSecurity, memberRefParent, hasSemantics, methodDefOrRef
        case customAttributeType, resolutionScope
        case memberForwarded, implementation

        var tables: [Int] {
            switch self {
            case .typeDefOrRef:        return [0x02, 0x01, 0x1B]
            case .hasConstant:         return [0x04, 0x08, 0x17]
            case .hasCustomAttribute:  return [0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x00,
                                               0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B, 0x20, 0x23,
                                               0x26, 0x27, 0x28, 0x2A, 0x2C, 0x2B]
            case .hasFieldMarshal:     return [0x04, 0x08]
            case .hasDeclSecurity:     return [0x02, 0x06, 0x20]
            case .memberRefParent:     return [0x02, 0x01, 0x1A, 0x06, 0x1B]
            case .hasSemantics:        return [0x14, 0x17]
            case .methodDefOrRef:      return [0x06, 0x0A]
            case .customAttributeType: return [0x06, 0x0A]
            case .resolutionScope:     return [0x00, 0x1A, 0x23, 0x01]
            case .memberForwarded:     return [0x04, 0x06]
            case .implementation:      return [0x26, 0x23, 0x27]
            }
        }

        /// Bits de tag : le nombre de familles, arrondi à la puissance de
        /// deux supérieure. `customAttributeType` en réserve 3 bien qu'il
        /// ne cible que deux tables (deux valeurs de tag sont inutilisées).
        var tagBits: Int {
            if case .customAttributeType = self { return 3 }
            var bits = 0
            while (1 << bits) < tables.count { bits += 1 }
            return bits
        }
    }

    /// La largeur de chaque famille de colonne, pour un en-tête donné.
    public struct ColumnWidths {
        public let string: Int
        public let guid: Int
        public let blob: Int
        let rowCount: [Int: Int]

        public init(heapSizes: UInt8, rowCount: [Int: Int]) {
            string = heapSizes & 0x01 != 0 ? 4 : 2
            guid = heapSizes & 0x02 != 0 ? 4 : 2
            blob = heapSizes & 0x04 != 0 ? 4 : 2
            self.rowCount = rowCount
        }

        /// Un index vers une table : 2 octets tant qu'elle tient sous
        /// 65 536 lignes.
        public func simple(_ table: Int) -> Int {
            (rowCount[table] ?? 0) < 0x1_0000 ? 2 : 4
        }

        /// Un index codé : la plus grande table visée doit tenir dans les
        /// bits qui restent une fois le tag retiré.
        public func coded(_ index: CodedIndex) -> Int {
            let biggest = index.tables.map { rowCount[$0] ?? 0 }.max() ?? 0
            return biggest < (1 << (16 - index.tagBits)) ? 2 : 4
        }

        /// La taille d'une ligne de chaque table 0x00–0x29 (§II.22) : jusqu'à
        /// `NestedClass`, la dernière que lit A5-T6. Les tables au-delà
        /// (génériques) ne précèdent rien de ce qu'on lit.
        func rowSizes() -> [Int: Int] {
            var sizes: [Int: Int] = [:]
            sizes[0x00] = 2 + string + 3 * guid                                      // Module
            sizes[0x01] = coded(.resolutionScope) + string + string                  // TypeRef
            sizes[0x02] = 4 + string + string + coded(.typeDefOrRef)
                + simple(0x04) + simple(0x06)                                        // TypeDef
            sizes[0x03] = simple(0x04)                                               // FieldPtr
            sizes[0x04] = 2 + string + blob                                          // Field
            sizes[0x05] = simple(0x06)                                               // MethodPtr
            sizes[0x06] = 4 + 2 + 2 + string + blob + simple(0x08)                   // MethodDef
            sizes[0x07] = simple(0x08)                                               // ParamPtr
            sizes[0x08] = 2 + 2 + string                                             // Param
            sizes[0x09] = simple(0x02) + coded(.typeDefOrRef)                        // InterfaceImpl
            sizes[0x0A] = coded(.memberRefParent) + string + blob                    // MemberRef
            sizes[0x0B] = 1 + 1 + coded(.hasConstant) + blob                         // Constant
            sizes[0x0C] = coded(.hasCustomAttribute) + coded(.customAttributeType) + blob
            sizes[0x0D] = coded(.hasFieldMarshal) + blob                             // FieldMarshal
            sizes[0x0E] = 2 + coded(.hasDeclSecurity) + blob                         // DeclSecurity
            sizes[0x0F] = 2 + 4 + simple(0x02)                                       // ClassLayout
            sizes[0x10] = 4 + simple(0x04)                                           // FieldLayout
            sizes[0x11] = blob                                                       // StandAloneSig
            sizes[0x12] = simple(0x02) + simple(0x14)                                // EventMap
            sizes[0x13] = simple(0x14)                                               // EventPtr
            sizes[0x14] = 2 + string + coded(.typeDefOrRef)                          // Event
            sizes[0x15] = simple(0x02) + simple(0x17)                                // PropertyMap
            sizes[0x16] = simple(0x17)                                               // PropertyPtr
            sizes[0x17] = 2 + string + blob                                          // Property
            sizes[0x18] = 2 + simple(0x06) + coded(.hasSemantics)                    // MethodSemantics
            sizes[0x19] = simple(0x02) + 2 * coded(.methodDefOrRef)                  // MethodImpl
            sizes[0x1A] = string                                                     // ModuleRef
            sizes[0x1B] = blob                                                       // TypeSpec
            sizes[0x1C] = 2 + coded(.memberForwarded) + string + simple(0x1A)        // ImplMap
            sizes[0x1D] = 4 + simple(0x04)                                           // FieldRVA
            sizes[0x1E] = 4 + 4                                                      // EncLog
            sizes[0x1F] = 4                                                          // EncMap
            sizes[0x20] = 4 + 4 * 2 + 4 + blob + string + string                     // Assembly
            sizes[0x21] = 4                                                          // AssemblyProcessor
            sizes[0x22] = 4 + 4 + 4                                                  // AssemblyOS
            sizes[0x23] = 4 * 2 + 4 + blob + string + string + blob                  // AssemblyRef
            sizes[0x24] = 4 + simple(0x23)                                           // AssemblyRefProcessor
            sizes[0x25] = 4 + 4 + 4 + simple(0x23)                                   // AssemblyRefOS
            sizes[0x26] = 4 + string + blob                                          // File
            sizes[0x27] = 4 + 4 + string + string + coded(.implementation)           // ExportedType
            sizes[0x28] = 4 + 4 + string + coded(.implementation)                    // ManifestResource
            sizes[0x29] = simple(0x02) + simple(0x02)                                // NestedClass
            return sizes
        }
    }

    // MARK: - Le fichier PE (§II.25)

    /// L'offset de la racine de métadonnées (`BSJB`) dans un fichier PE,
    /// via le dossier de données 14 (en-tête CLI). `nil` dès qu'une borne
    /// manque : un fichier tronqué ou étranger se refuse, il ne se devine
    /// pas.
    public static func metadataRootOffset(inPE bytes: [UInt8]) -> Int? {
        guard bytes.count > 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A else { return nil }
        guard let peOffset = u32(bytes, 0x3C).map(Int.init), peOffset + 24 <= bytes.count,
              u32(bytes, peOffset) == 0x0000_4550 else { return nil }
        guard let sections = u16(bytes, peOffset + 6).map(Int.init),
              let optionalSize = u16(bytes, peOffset + 20).map(Int.init) else { return nil }
        let optionalHeader = peOffset + 24
        guard optionalSize >= 16, optionalHeader + optionalSize <= bytes.count,
              let magic = u16(bytes, optionalHeader) else { return nil }
        let directories = optionalHeader + (magic == 0x20B ? 112 : 96)
        guard directories + 15 * 8 <= bytes.count,
              let cliRVA = u32(bytes, directories + 14 * 8).map(Int.init), cliRVA > 0,
              let cliOffset = offset(ofRVA: cliRVA, in: bytes,
                                     sectionsAt: optionalHeader + optionalSize, count: sections),
              cliOffset + 16 <= bytes.count,
              let metadataRVA = u32(bytes, cliOffset + 8).map(Int.init), metadataRVA > 0
        else { return nil }
        guard let root = offset(ofRVA: metadataRVA, in: bytes,
                                sectionsAt: optionalHeader + optionalSize, count: sections),
              root + 4 <= bytes.count, u32(bytes, root) == 0x424A_5342 else { return nil }
        return root
    }

    private static func offset(ofRVA rva: Int, in bytes: [UInt8],
                               sectionsAt start: Int, count: Int) -> Int? {
        for section in 0..<count {
            let header = start + section * 40
            guard header + 40 <= bytes.count,
                  let virtualAddress = u32(bytes, header + 12).map(Int.init),
                  let rawSize = u32(bytes, header + 16).map(Int.init),
                  let rawPointer = u32(bytes, header + 20).map(Int.init) else { continue }
            if rva >= virtualAddress, rva < virtualAddress + max(rawSize, 1) {
                let result = rva - virtualAddress + rawPointer
                return result < bytes.count ? result : nil
            }
        }
        return nil
    }

    // MARK: - La racine de métadonnées (§II.24.2)

    /// La racine de métadonnées analysée : ses heaps et son stream de
    /// tables. Partagée par les choix de config (C4-T11) et les
    /// dépendances cachées (A5-T6).
    struct MetadataFile {
        let bytes: [UInt8]
        let strings: Range<Int>
        /// `#US` : absent d'un assembly sans littéral de chaîne.
        let userStringHeap: Range<Int>?
        let blobs: Range<Int>
        let rowCount: [Int: Int]
        let rowSize: [Int: Int]
        let firstRowOffset: Int

        init?(bytes: [UInt8], root: Int) {
            self.bytes = bytes
            // §II.24.2.1 — signature, versions, longueur de la chaîne de
            // version (padée à 4), drapeaux, nombre de streams.
            guard let versionLength = DotNetMetadata.u32(bytes, root + 12).map(Int.init) else { return nil }
            var cursor = root + 16 + versionLength
            guard let streamCount = DotNetMetadata.u16(bytes, cursor + 2).map(Int.init) else { return nil }
            cursor += 4

            var stringsRange: Range<Int>?
            var userStringsRange: Range<Int>?
            var blobRange: Range<Int>?
            var tablesRange: Range<Int>?
            for _ in 0..<streamCount {
                guard let offset = DotNetMetadata.u32(bytes, cursor).map(Int.init),
                      let size = DotNetMetadata.u32(bytes, cursor + 4).map(Int.init) else { return nil }
                cursor += 8
                var end = cursor
                while end < bytes.count, bytes[end] != 0 { end += 1 }
                guard end < bytes.count,
                      let name = String(bytes: bytes[cursor..<end], encoding: .ascii) else { return nil }
                cursor = end + 1
                cursor = (cursor + 3) & ~3   // le nom est padé à 4 octets
                let range = (root + offset)..<(root + offset + size)
                guard range.upperBound <= bytes.count else { return nil }
                switch name {
                case "#Strings": stringsRange = range
                case "#US":      userStringsRange = range
                case "#Blob":    blobRange = range
                case "#~":       tablesRange = range
                // `#-` : tables non compressées. Absent du parc, schéma
                // distinct — ne pas le lire comme un `#~`.
                default: break
                }
            }
            guard let stringsRange, let blobRange, let tablesRange else { return nil }
            strings = stringsRange
            userStringHeap = userStringsRange
            blobs = blobRange

            // §II.24.2.6 — en-tête du stream de tables.
            let header = tablesRange.lowerBound
            guard header + 24 <= bytes.count,
                  let valid = DotNetMetadata.u64(bytes, header + 8) else { return nil }
            let heapSizes = bytes[header + 6]
            var counts: [Int: Int] = [:]
            var countCursor = header + 24
            for table in 0..<64 where valid & (1 << UInt64(table)) != 0 {
                guard let count = DotNetMetadata.u32(bytes, countCursor).map(Int.init) else { return nil }
                counts[table] = count
                countCursor += 4
            }
            // Les tables d'indirection rendraient le parcours par plage
            // faux : abandonner plutôt que répondre à côté.
            for indirection in [0x03, 0x05, 0x07, 0x16] where (counts[indirection] ?? 0) > 0 {
                return nil
            }
            rowCount = counts
            rowSize = DotNetMetadata.ColumnWidths(heapSizes: heapSizes, rowCount: counts).rowSizes()
            firstRowOffset = countCursor
            widths = DotNetMetadata.ColumnWidths(heapSizes: heapSizes, rowCount: counts)
        }

        let widths: DotNetMetadata.ColumnWidths

        /// L'offset de la première ligne d'une table : la somme des tailles
        /// de **toutes** celles qui la précèdent.
        func offset(ofTable table: Int) -> Int? {
            guard (rowCount[table] ?? 0) > 0, rowSize[table] != nil else { return nil }
            var offset = firstRowOffset
            for earlier in 0..<table where (rowCount[earlier] ?? 0) > 0 {
                guard let size = rowSize[earlier] else { return nil }
                offset += size * (rowCount[earlier] ?? 0)
            }
            return offset
        }

        /// La valeur d'une colonne de `width` octets, à `column` octets du
        /// début de la ligne `row` (numérotée à partir de 1).
        func column(table: Int, row: Int, at column: Int, width: Int) -> Int? {
            guard let base = offset(ofTable: table), let size = rowSize[table] else { return nil }
            let at = base + (row - 1) * size + column
            if width == 2 { return DotNetMetadata.u16(bytes, at).map(Int.init) }
            return DotNetMetadata.u32(bytes, at).map(Int.init)
        }

        /// Une chaîne de `#Strings`, terminée par zéro.
        func string(at index: Int) -> String? {
            let start = strings.lowerBound + index
            guard start >= strings.lowerBound, start < strings.upperBound else { return nil }
            var end = start
            while end < strings.upperBound, bytes[end] != 0 { end += 1 }
            return String(bytes: bytes[start..<end], encoding: .utf8)
        }

        /// Un item de `#Blob` : longueur compressée, puis les octets.
        func blob(at index: Int) -> [UInt8]? {
            var position = blobs.lowerBound + index
            guard position >= blobs.lowerBound, position < blobs.upperBound,
                  let length = DotNetMetadata.compressedUInt(bytes, &position),
                  position + length <= blobs.upperBound else { return nil }
            return Array(bytes[position..<(position + length)])
        }

        /// La fin d'une plage déclarée par un index de liste : le début de
        /// la ligne suivante, ou **le bout de la table visée** pour la
        /// dernière ligne. C'est exactement le cas que seul un assembly
        /// réel exerce (`Outer.NestedMode`, dernier TypeDef de la fixture).
        func listEnd(table: Int, row: Int, column: Int, width: Int, target: Int) -> Int? {
            if row < (rowCount[table] ?? 0) {
                return self.column(table: table, row: row + 1, at: column, width: width)
            }
            return (rowCount[target] ?? 0) + 1
        }
    }

    // MARK: - Lectures bornées

    static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    static func u64(_ bytes: [UInt8], _ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        var value: UInt64 = 0
        for byte in 0..<8 { value |= UInt64(bytes[offset + byte]) << (8 * byte) }
        return value
    }
}
