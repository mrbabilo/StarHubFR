import Foundation

/// Erreur de décompression LZX — la cause unique exposée par le décodeur.
/// Toute dérive interne (fin de flux, arbre invalide, dépassement de bloc)
/// y est repliée avec sa cause.
public enum LzxdError: Error, Sendable {
    case corruptStream(String)
}

/// Tables de positions LZX — `FOOTER_BITS` et `BASE_POSITION` de `block.rs`,
/// générées par les formules que le Rust donne en commentaire (valeurs
/// identiques aux tableaux littéraux, vérifiées jusqu'au slot 289).
private enum LzxdPositionTables {
    /// Bits de suffixe par position slot.
    static let footerBits: [Int] = (0..<290).map { slot in
        slot < 4 ? 0 : (slot >= 36 ? 17 : (slot - 2) / 2)
    }

    /// Base d'offset par position slot : base[i] = base[i−1] + 2^footer[i−1].
    static let basePosition: [UInt32] = {
        var table: [UInt32] = [0]
        for slot in 1..<290 {
            table.append(table[slot - 1] + (1 << UInt32(footerBits[slot - 1])))
        }
        return table
    }()
}

/// Un élément décodé d'un bloc — `Decoded` de `block.rs`.
enum LzxdDecoded {
    case single(UInt8)
    case match(offset: Int, length: Int)
    case read(Int)
}

/// Le genre du bloc courant — `Kind` de `block.rs`.
enum LzxdBlockKind {
    case verbatim(mainTree: LzxdTree, lengthTree: LzxdTree?)
    case alignedOffset(alignedOffsetTree: LzxdTree, mainTree: LzxdTree, lengthTree: LzxdTree?)
    case uncompressed(r0: UInt32, r1: UInt32, r2: UInt32)
}

/// La tête du corps d'un bloc (tout sauf la queue de données) — `Block`
/// de `block.rs`.
struct LzxdBlock {
    var remaining: Int
    var size: Int
    var kind: LzxdBlockKind

    /// Lit l'en-tête de bloc : 3 bits de type, taille `u24` big-endian,
    /// puis selon le genre les arbres (verbatim/aligné) ou l'alignement et
    /// R0/R1/R2 (non compressé).
    static func read(_ stream: inout LzxdBitstream,
                     mainTree: inout LzxdCanonicalTree,
                     lengthTree: inout LzxdCanonicalTree,
                     windowSize: LzxdWindowSize) throws -> LzxdBlock {
        let kindBits = UInt8(try stream.readBits(3))
        let size = Int(try stream.readU24BE())
        guard size != 0 else { throw LzxdError.corruptStream("taille de bloc nulle") }

        let kind: LzxdBlockKind
        switch kindBits {
        case 0b001:
            try readMainAndLengthTrees(&stream, mainTree: &mainTree,
                                       lengthTree: &lengthTree, windowSize: windowSize)
            kind = .verbatim(mainTree: try mainTree.createInstance(),
                             lengthTree: try lengthTree.createInstanceAllowEmpty())
        case 0b010:
            // Bloc à offset aligné : 8 longueurs de 3 bits, sans delta —
            // l'arbre est reconstruit à chaque bloc aligné.
            var alignedLengths = [UInt8]()
            alignedLengths.reserveCapacity(8)
            for _ in 0..<8 { alignedLengths.append(UInt8(try stream.readBits(3))) }
            let alignedTree = try LzxdTree(pathLengths: alignedLengths)

            try readMainAndLengthTrees(&stream, mainTree: &mainTree,
                                       lengthTree: &lengthTree, windowSize: windowSize)
            kind = .alignedOffset(alignedOffsetTree: alignedTree,
                                  mainTree: try mainTree.createInstance(),
                                  lengthTree: try lengthTree.createInstanceAllowEmpty())
        case 0b011:
            try stream.align()
            kind = .uncompressed(r0: UInt32(try stream.readU32LE()),
                                 r1: UInt32(try stream.readU32LE()),
                                 r2: UInt32(try stream.readU32LE()))
        default:
            throw LzxdError.corruptStream("type de bloc \(kindBits) invalide")
        }

        return LzxdBlock(remaining: size, size: size, kind: kind)
    }

    /// Décode l'élément suivant du bloc.
    func decodeElement(_ stream: inout LzxdBitstream, r: inout [UInt32]) throws -> LzxdDecoded {
        switch kind {
        case let .verbatim(mainTree, lengthTree):
            return try Self.decodeCompressedElement(&stream, r: &r, alignedOffsetTree: nil,
                                                    mainTree: mainTree, lengthTree: lengthTree)
        case let .alignedOffset(alignedTree, mainTree, lengthTree):
            return try Self.decodeCompressedElement(&stream, r: &r, alignedOffsetTree: alignedTree,
                                                    mainTree: mainTree, lengthTree: lengthTree)
        case let .uncompressed(r0, r1, r2):
            r[0] = r0; r[1] = r1; r[2] = r2
            return .read(remaining)
        }
    }

    /// Les pré-arbres des arbres principal et de longueurs — utilisé par les
    /// blocs verbatim et alignés.
    private static func readMainAndLengthTrees(
        _ stream: inout LzxdBitstream,
        mainTree: inout LzxdCanonicalTree,
        lengthTree: inout LzxdCanonicalTree,
        windowSize: LzxdWindowSize
    ) throws {
        let slotCount = 256 + 8 * windowSize.positionSlots
        try mainTree.updateRange(withPretree: &stream, range: 0..<256)
        try mainTree.updateRange(withPretree: &stream, range: 256..<slotCount)
        try lengthTree.updateRange(withPretree: &stream, range: 0..<249)
    }

    /// Décode un littéral ou une correspondance LZ77 (offset + longueur) —
    /// `decode_element` de `block.rs`.
    ///
    /// N.B. le Rust laisse délibérément commenté le décodage des longueurs
    /// ≥ 257 (préfixes 0b0/10/110/111) : sur les `.xnb` 64 Kio, l'activer
    /// casse la décompression. Le portage s'abtient pareillement.
    private static func decodeCompressedElement(
        _ stream: inout LzxdBitstream,
        r: inout [UInt32],
        alignedOffsetTree: LzxdTree?,
        mainTree: LzxdTree,
        lengthTree: LzxdTree?
    ) throws -> LzxdDecoded {
        let mainElement = Int(try mainTree.decodeElement(with: &stream))

        // En dessous de 256 : un littéral.
        guard mainElement >= 256 else { return .single(UInt8(mainElement)) }

        // Une correspondance : en-tête de longueur (3 bits dans le symbole),
        // puis éventuellement un pied lu dans l'arbre des longueurs.
        let lengthHeader = (mainElement - 256) & 7
        let matchLength: Int
        if lengthHeader == 7 {
            guard let lengthTree else {
                throw LzxdError.corruptStream("arbre des longueurs requis mais vide")
            }
            matchLength = Int(try lengthTree.decodeElement(with: &stream)) + 7 + 2
        } else {
            matchLength = lengthHeader + 2
        }

        let positionSlot = (mainElement - 256) >> 3

        let matchOffset: Int
        switch positionSlot {
        case 0:
            matchOffset = Int(r[0])
        case 1:
            matchOffset = Int(r[1])
            r.swapAt(0, 1)
        case 2:
            matchOffset = Int(r[2])
            r.swapAt(0, 2)
        default:
            // Offset explicite : base du slot + bits verbatim (+ bits alignés).
            let offsetBits = LzxdPositionTables.footerBits[positionSlot]
            let formatted: UInt32
            if let alignedTree = alignedOffsetTree {
                if offsetBits >= 3 {
                    let verbatimBits = (try stream.readBits(offsetBits - 3)) << 3
                    let alignedBits = UInt32(try alignedTree.decodeElement(with: &stream))
                    formatted = LzxdPositionTables.basePosition[positionSlot]
                        &+ verbatimBits &+ alignedBits
                } else {
                    let rawBits = try stream.readBits(offsetBits)
                    formatted = LzxdPositionTables.basePosition[positionSlot] &+ rawBits
                }
            } else {
                let rawBits = try stream.readBits(offsetBits)
                formatted = LzxdPositionTables.basePosition[positionSlot] &+ rawBits
            }
            matchOffset = Int(formatted) - 2
            // File des offsets récents (moins récemment utilisés sort).
            r[2] = r[1]
            r[1] = r[0]
            r[0] = UInt32(matchOffset)
        }

        return .match(offset: matchOffset, length: matchLength)
    }
}

/// Le décodeur LZX complet — translittération de `Lzxd` dans `lib.rs` de
/// lzxd v0.2.6 (Lonami — https://github.com/Lonami/lzxd, commit `4f477bd`,
/// MIT OR Apache-2.0). Le Rust est la vérité : en cas de divergence, le
/// Swift a tort — l'oracle StardewXnbHack tranche (spéc P2b §4/§9).
///
/// L'état (fenêtre, arbres canoniques, R0/R1/R2, bloc courant, décalage de
/// fichier) vit dans le décodeur, pas dans les morceaux : un même décodeur
/// enchaîne les morceaux du framing XNB. La tranche rendue est valide
/// jusqu'au prochain appel, comme l'emprunt `&[u8]` du Rust.
public struct LzxdDecoder {
    private let windowSize: LzxdWindowSize
    private var window: LzxdWindow
    /// Arbres persistants : les deltas du prochain bloc s'y appliquent.
    private var mainTree: LzxdCanonicalTree
    private var lengthTree: LzxdCanonicalTree
    /// Les trois derniers offsets de match réels — initiaux à (1, 1, 1).
    private var r: [UInt32]
    /// Décalage courant dans les données décompressées (pour E8).
    private var chunkOffset: Int
    /// Le premier morceau porte à lui seul le drapeau E8.
    private var firstChunkRead: Bool
    private var currentBlock: LzxdBlock
    /// Taille de traduction E8 (`nil` = traduction désactivée) + tampon réutilisé.
    private var e8TranslationSize: Int32?
    private var e8Buffer: [UInt8]

    public init(window: LzxdWindowSize) {
        self.windowSize = window
        self.window = window.makeWindow()
        mainTree = LzxdCanonicalTree(slotCount: 256 + 8 * window.positionSlots)
        lengthTree = LzxdCanonicalTree(slotCount: 249)
        r = [1, 1, 1]
        chunkOffset = 0
        firstChunkRead = false
        currentBlock = LzxdBlock(remaining: 0, size: 0, kind: .uncompressed(r0: 1, r1: 1, r2: 1))
        e8TranslationSize = nil
        e8Buffer = []
    }

    /// Décode le prochain morceau. `outputLength` = taille de sortie attendue
    /// de ce morceau (au plus `MAX_CHUNK_SIZE`).
    public mutating func decompressNext(_ chunk: ArraySlice<UInt8>,
                                        outputLength: Int) throws -> ArraySlice<UInt8> {
        guard outputLength > 0 else {
            throw LzxdError.corruptStream("taille de sortie nulle ou négative")
        }
        guard outputLength <= LzxdWindowSize.maxChunkSize else {
            throw LzxdError.corruptStream("morceau plus long que MAX_CHUNK_SIZE")
        }
        do {
            return try decompress(chunk, outputLength: outputLength)
        } catch let error as LzxdError {
            throw error
        } catch {
            throw Self.wrap(error)
        }
    }

    private mutating func decompress(_ chunk: ArraySlice<UInt8>,
                                     outputLength: Int) throws -> ArraySlice<UInt8> {
        var stream = LzxdBitstream(chunk)
        try readFirstChunkIfNeeded(&stream)

        var decodedLen = 0
        while decodedLen != outputLength {
            if currentBlock.remaining == 0 {
                // Réalignement : un bloc non compressé de taille impaire
                // laisse un octet de bourrage (gcab/libmspack pareil).
                if case .uncompressed = currentBlock.kind, currentBlock.size % 2 != 0 {
                    _ = stream.readByte()
                }
                currentBlock = try LzxdBlock.read(&stream, mainTree: &mainTree,
                                                  lengthTree: &lengthTree,
                                                  windowSize: windowSize)
            }

            let decoded = try currentBlock.decodeElement(&stream, r: &r)

            let advance: Int
            switch decoded {
            case let .single(value):
                window.push(value)
                advance = 1
            case let .match(offset, length):
                window.copyFromSelf(offset: offset, length: length)
                advance = length
            case let .read(length):
                // Jusqu'à la fin du morceau : un bloc peut déborder.
                let bounded = min(stream.remainingBytes, length)
                try window.copyFromBitstream(&stream, length: bounded)
                advance = bounded
            }

            guard advance > 0 else {
                throw LzxdError.corruptStream("décodage sans progression")
            }
            decodedLen += advance
            guard currentBlock.remaining >= advance else {
                throw LzxdError.corruptStream("dépassement de bloc (OverreadBlock)")
            }
            currentBlock.remaining -= advance
        }

        let offset = chunkOffset
        chunkOffset += decodedLen

        let view = window.pastView(decodedLen)
        guard let translationSize = e8TranslationSize else { return view }
        // Fixups E8 coupés au-delà d'1 Gio, ou sur un morceau trop court.
        if offset >= 0x4000_0000 || decodedLen <= 10 { return view }
        e8Buffer = Array(view)
        Self.postprocess(translationSize: translationSize, chunkOffset: offset,
                         idata: &e8Buffer)
        return e8Buffer[0..<decodedLen]
    }

    /// Le premier bit du premier morceau : drapeau E8, puis sa taille sur
    /// 32 bits si activé.
    private mutating func readFirstChunkIfNeeded(_ stream: inout LzxdBitstream) throws {
        guard !firstChunkRead else { return }
        firstChunkRead = true
        if try stream.readBit() != 0 {
            e8TranslationSize = Int32(truncatingIfNeeded: try stream.readBits(32))
        }
    }

    /// Traduction E8 : chaque `0xE8` suivi d'une valeur dans le fichier est
    /// réécrite en relatif — `postprocess` de `lib.rs`.
    private static func postprocess(translationSize: Int32, chunkOffset: Int,
                                    idata: inout [UInt8]) {
        var processed = 0
        while let pos = idata[processed...].firstIndex(of: 0xE8) {
            // Fixup coupé à moins de 10 octets de la fin du morceau.
            if idata.count - pos <= 10 { break }

            let currentPointer = Int32(truncatingIfNeeded: chunkOffset &+ pos)
            let absVal = Int32(bitPattern:
                UInt32(idata[pos + 1])
                | UInt32(idata[pos + 2]) << 8
                | UInt32(idata[pos + 3]) << 16
                | UInt32(idata[pos + 4]) << 24)
            if absVal >= -currentPointer && absVal < translationSize {
                let relVal = absVal > 0 ? absVal &- currentPointer
                                        : absVal &+ translationSize
                let bits = UInt32(bitPattern: relVal)
                idata[pos + 1] = UInt8(truncatingIfNeeded: bits)
                idata[pos + 2] = UInt8(truncatingIfNeeded: bits >> 8)
                idata[pos + 3] = UInt8(truncatingIfNeeded: bits >> 16)
                idata[pos + 4] = UInt8(truncatingIfNeeded: bits >> 24)
            }
            processed = pos + 5
        }
    }

    /// Replie une erreur interne (bitstream, arbres, fenêtre) dans la cause
    /// publique unique.
    private static func wrap(_ error: Error) -> LzxdError {
        switch error {
        case LzxdBitstream.Error.outOfData:
            return .corruptStream("fin de flux prématurée")
        case LzxdTreeError.invalidPathLengths:
            return .corruptStream("longueurs de chemins d'arbre invalides")
        case LzxdTreeError.emptyTree:
            return .corruptStream("arbre requis vide")
        case LzxdTreeError.invalidPretreeRle:
            return .corruptStream("run de pré-arbre hors de l'arbre")
        case let LzxdTreeError.invalidPretreeElement(element):
            return .corruptStream("élément de pré-arbre invalide (\(element))")
        case LzxdWindow.Error.windowTooSmall:
            return .corruptStream("fenêtre trop petite pour le bloc")
        default:
            return .corruptStream(String(describing: error))
        }
    }
}
