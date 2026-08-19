import Foundation

/// Erreurs des arbres Huffman LZX — miroir des `DecodeFailed` de `tree.rs`.
enum LzxdTreeError: Error, Equatable {
    /// Longueurs de chemins incohérentes (arbre incomplet ou sursouscrit).
    case invalidPathLengths
    /// `createInstance` sur un arbre entièrement vide.
    case emptyTree
    /// Un code de run (17/18/19) dépasse la fin de l'arbre.
    case invalidPretreeRle
    /// Le pré-arbre a décodé un élément hors des valeurs légales.
    case invalidPretreeElement(UInt16)
}

/// L'arbre de décodage, immuable — translittération de `Tree` dans `tree.rs`
/// de lzxd v0.2.6 (Lonami — https://github.com/Lonami/lzxd, commit `4f477bd`,
/// MIT OR Apache-2.0). Le Rust est la vérité : en cas de divergence, le Swift
/// a tort.
///
/// Le décodage regarde `largestLength` bits d'un coup (peek) et lit la table
/// directement : une seule opération, jamais une descente bit à bit — l'idée
/// vient de xnbcli, crédit du Rust.
struct LzxdTree {
    /// Longueurs de chemins par symbole (0 = absent de l'arbre).
    private let pathLengths: [UInt8]
    /// La plus grande longueur — le nombre de bits peekés par décodage.
    private let largestLength: Int
    /// Table de décodage : `1 << largestLength` entrées, indexées par les bits
    /// peekés ; chaque entrée est le symbole décodé.
    private let huffmanTree: [UInt16]

    init(pathLengths: [UInt8]) throws {
        self = try LzxdCanonicalTree(pathLengths: pathLengths).createInstance()
    }

    fileprivate init(pathLengths: [UInt8], largestLength: Int, huffmanTree: [UInt16]) {
        self.pathLengths = pathLengths
        self.largestLength = largestLength
        self.huffmanTree = huffmanTree
    }

    /// Décode un élément : peek du nombre de bits du plus grand code, lecture
    /// table, puis avancement du flux d'exactement la longueur du code obtenu.
    func decodeElement(with stream: inout LzxdBitstream) throws -> UInt16 {
        let code = huffmanTree[Int(stream.peekBits(largestLength))]
        _ = try stream.readBits(Int(pathLengths[Int(code)]))
        return code
    }
}

/// Le bâtisseur : longueurs persistantes entre blocs, mises à jour par deltas
/// encodés via un pré-arbre — `CanonicalTree` dans `tree.rs`.
struct LzxdCanonicalTree {
    /// Longueurs par élément : 0 = fréquence nulle (absent de l'arbre). Le
    /// premier arbre part de zéro — le delta initial se calcule contre lui.
    private(set) var pathLengths: [UInt8]

    init(slotCount: Int) {
        precondition(slotCount > 0, "un arbre n'a pas zéro élément (expect du Rust)")
        pathLengths = [UInt8](repeating: 0, count: slotCount)
    }

    fileprivate init(pathLengths: [UInt8]) {
        self.pathLengths = pathLengths
    }

    /// Instancie l'arbre de décodage ; `nil` si toutes les longueurs sont
    /// nulles (arbre vide — c'est légal).
    func createInstanceAllowEmpty() throws -> LzxdTree? {
        guard let largest = pathLengths.max(), largest > 0 else { return nil }

        // Allocation canonique : les codes sont attribués par longueur
        // croissante puis ordre séquentiel des symboles, chacun répété
        // 2^(largest − longueur) fois. La table doit se remplir exactement.
        var huffmanTree = [UInt16](repeating: 0, count: 1 << largest)
        var pos = 0
        for bit in 1...largest {
            let amount = 1 << (largest - bit)
            for code in pathLengths.indices where pathLengths[code] == bit {
                guard pos + amount <= huffmanTree.count else {
                    throw LzxdTreeError.invalidPathLengths
                }
                for i in pos..<(pos + amount) { huffmanTree[i] = UInt16(code) }
                pos += amount
            }
        }
        guard pos == huffmanTree.count else { throw LzxdTreeError.invalidPathLengths }

        return LzxdTree(pathLengths: pathLengths, largestLength: Int(largest),
                        huffmanTree: huffmanTree)
    }

    /// Comme `createInstanceAllowEmpty`, mais un arbre vide est une erreur.
    func createInstance() throws -> LzxdTree {
        guard let tree = try createInstanceAllowEmpty() else {
            throw LzxdTreeError.emptyTree
        }
        return tree
    }

    /// Met à jour `range` depuis le flux : un pré-arbre de 20 éléments (80
    /// bits de longueurs, 4 bits chacune) encode les codes, puis chaque code
    /// est soit un delta mod 17, soit un run (17 : 4+zéros zéros ; 18 :
    /// 20+zéros zéros ; 19 : delta répété 4+same fois).
    mutating func updateRange(withPretree stream: inout LzxdBitstream,
                              range: Range<Int>) throws {
        precondition(range.lowerBound >= 0 && range.upperBound <= pathLengths.count,
                     "updateRange: hors de l'arbre")

        var pretreeLengths = [UInt8]()
        pretreeLengths.reserveCapacity(20)
        for _ in 0..<20 { pretreeLengths.append(UInt8(try stream.readBits(4))) }
        let pretree = try LzxdTree(pathLengths: pretreeLengths)

        var i = range.lowerBound
        while i < range.upperBound {
            let code = try pretree.decodeElement(with: &stream)
            switch code {
            case 0...16:
                pathLengths[i] = (17 + pathLengths[i] - UInt8(code)) % 17
                i += 1
            case 17:
                let end = i + Int(try stream.readBits(4)) + 4
                guard end <= pathLengths.count else { throw LzxdTreeError.invalidPretreeRle }
                for j in i..<end { pathLengths[j] = 0 }
                i = end
            case 18:
                let end = i + Int(try stream.readBits(5)) + 20
                guard end <= pathLengths.count else { throw LzxdTreeError.invalidPretreeRle }
                for j in i..<end { pathLengths[j] = 0 }
                i = end
            case 19:
                let same = Int(try stream.readBits(1))
                // « Decode new code » : le delta qui suit est borné à [0, 16].
                let next = try pretree.decodeElement(with: &stream)
                guard next <= 16 else { throw LzxdTreeError.invalidPretreeElement(next) }
                let value = (17 + pathLengths[i] - UInt8(next)) % 17
                let end = i + same + 4
                guard end <= pathLengths.count else { throw LzxdTreeError.invalidPretreeRle }
                for j in i..<end { pathLengths[j] = value }
                i = end
            default:
                throw LzxdTreeError.invalidPretreeElement(code)
            }
        }
    }
}
