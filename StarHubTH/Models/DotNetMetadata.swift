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

        /// La taille d'une ligne de chaque table 0x00–0x17 (§II.22). Les
        /// tables au-delà ne sont jamais lues ici : seuls leurs **comptes**
        /// comptent, et ils viennent de l'en-tête.
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
