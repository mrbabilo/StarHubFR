import Foundation

/// Flux de bits du format XMem/LZX des `.xnb` — translittération de
/// `bitstream.rs` de lzxd v0.2.6 (Lonami — https://github.com/Lonami/lzxd,
/// commit `4f477bd`, MIT OR Apache-2.0). Le Rust est la vérité : en cas de
/// divergence, le Swift a tort (règle du portage, spec P2b §4).
///
/// Le flux n'est pas une suite d'octets MSB-first : c'est une suite de **mots
/// de 16 bits little-endian** (« byte-swapped ») lus MSB-first — les premiers
/// bits du flux viennent du *second* octet de chaque paire (doc de tête de
/// `bitstream.rs`, reprise de la spec XMemDecode). Écrire « l'octet 0 d'abord »
/// au lieu de « le mot 0 d'abord » décode du bruit : la mémoire de l'ordre
/// réside ici, à la source.
///
/// Divergence assumée et bornée : le Rust panique quand un mot déborde d'un
/// tampon réduit à un octet isolé ; ici cet octet livre ses 8 bits réels puis
/// toute lecture au-delà lève `outOfData`. Aucun flux que le Rust décode sans
/// paniquer ne se décode autrement ici — l'oracle StardewXnbHack en juge.
struct LzxdBitstream {
    enum Error: Swift.Error, Equatable {
        case outOfData
    }

    /// Octets restants (consommés par mots de 2, ou à l'octet par `readRaw`).
    private var buffer: ArraySlice<UInt8>
    /// Mot courant du flux, tourné au fil des lectures (`n` dans le Rust).
    private var n: UInt16
    /// Bits réels restants dans le mot courant.
    private var remaining: Int

    init(_ bytes: [UInt8]) {
        self.init(bytes[...])
    }

    init(_ bytes: ArraySlice<UInt8>) {
        buffer = bytes
        n = 0
        remaining = 0
    }

    // MARK: - Lecture (bitstream.rs)

    mutating func readBit() throws -> UInt16 {
        if remaining == 0 {
            try advanceBuffer()
        }
        remaining -= 1
        n = rotl16(n, 1)
        return n & 1
    }

    /// Lit jusqu'à 32 bits, MSB-first à travers les mots de 16 bits.
    mutating func readBits(_ bits: Int) throws -> UInt32 {
        precondition(bits <= 32, "readBits: 32 bits au plus, comme le Rust")
        if bits <= 16 {
            return UInt32(try readBitsOneword(bits))
        }
        let w0 = UInt32(try readBitsOneword(16))
        let w1 = UInt32(try readBitsOneword(bits - 16))
        return (w0 << (bits - 16)) | w1
    }

    /// Lit sans consommer. Au-delà de la fin du morceau, fait comme si des
    /// zéros suivaient (le décodeur peek par anticipation ; le Rust pareil).
    func peekBits(_ bits: Int) -> UInt32 {
        precondition(bits <= 32, "peekBits: 32 bits au plus, comme le Rust")
        if bits <= 16 {
            return UInt32(peekBitsOneword(bits))
        }
        // Copie du flux : lecture réelle du premier mot, peek du second.
        var advanced = self
        let w0 = UInt32((try? advanced.readBitsOneword(16)) ?? 0)
        let w1 = UInt32(advanced.peekBitsOneword(bits - 16))
        return (w0 << (bits - 16)) | w1
    }

    /// Saute la fin du mot de 16 bits courant. Mot déjà épuisé → le suivant
    /// est avalé entier (fidèle à `bitstream.rs::align`).
    mutating func align() throws {
        if remaining == 0 {
            _ = try readBits(16)
        } else {
            remaining = 0
        }
    }

    /// Copie `output.count` octets bruts depuis le tampon, représentation
    /// ignorée. Tampon trop court → `outOfData` avant toute écriture.
    mutating func readRaw(into output: inout [UInt8]) throws {
        guard buffer.count >= output.count else { throw Error.outOfData }
        output = Array(buffer.prefix(output.count))
        buffer = buffer.dropFirst(output.count)
    }

    /// Un octet brut hors bitstream, ou `nil` si le tampon est vide.
    mutating func readByte() -> UInt8? {
        guard let byte = buffer.first else { return nil }
        buffer = buffer.dropFirst()
        return byte
    }

    /// Un `u32` little-endian — composé de deux mots, ce qui redonne la
    /// lecture LE des 4 octets bruts suivants.
    mutating func readU32LE() throws -> UInt32 {
        let lo = UInt32(try readBitsOneword(16))
        let hi = UInt32(try readBitsOneword(16))
        return lo | (hi << 16)
    }

    /// La taille de bloc LZX : un `u24` big-endian dans le flux de bits.
    mutating func readU24BE() throws -> UInt32 {
        let hi = try readBits(16)
        let lo = try readBits(8)
        return (hi << 8) | lo
    }

    var remainingBytes: Int { buffer.count }

    // MARK: - Internes (bitstream.rs : advance_buffer, *_oneword)

    /// Charge le mot suivant. Un octet isolé en fin de tampon charge ses 8
    /// bits réels seuls (le Rust paniquerait sur le second octet manquant).
    private mutating func advanceBuffer() throws {
        if buffer.isEmpty { throw Error.outOfData }
        let start = buffer.startIndex
        let low = UInt16(buffer[start])
        if buffer.count >= 2 {
            n = low | (UInt16(buffer[start + 1]) << 8)
            remaining = 16
            buffer = buffer.dropFirst(2)
        } else {
            // Octet isolé : il occupe la position des premiers bits du mot
            // (poids fort), les 8 suivants n'existent pas.
            n = low << 8
            remaining = 8
            buffer = buffer.dropFirst()
        }
    }

    /// Lit au plus un mot (16 bits) — `read_bits_oneword` dans le Rust.
    private mutating func readBitsOneword(_ bits: Int) throws -> UInt16 {
        precondition(bits <= 16, "readBitsOneword: un mot au plus")
        if bits <= remaining {
            remaining -= bits
            n = rotl16(n, bits)
            return n & mask16(bits)
        }
        // Le morceau haut vient du mot courant, le bas du suivant.
        let hi = rotl16(n, remaining) & mask16(remaining)
        let lowBits = bits - remaining
        try advanceBuffer()
        // Une queue d'un octet ne porte que 8 bits réels : une lecture qui
        // déborde échoue avant tout retour partiel.
        guard remaining >= lowBits else { throw Error.outOfData }
        remaining -= lowBits
        n = rotl16(n, lowBits)
        let lo = n & mask16(lowBits)
        return UInt16(truncatingIfNeeded: (UInt32(hi) << lowBits) | UInt32(lo))
    }

    /// Peek au plus un mot, sans avancer — `peek_bits_oneword` dans le Rust.
    private func peekBitsOneword(_ bits: Int) -> UInt16 {
        precondition(bits <= 16, "peekBitsOneword: un mot au plus")
        if bits <= remaining {
            return rotl16(n, bits) & mask16(bits)
        }
        let hi = rotl16(n, remaining) & mask16(remaining)
        let lowBits = bits - remaining
        // On peut peeker au-delà de la fin du morceau : des zéros suivent.
        // Une queue d'un octet se charge comme dans `advanceBuffer`.
        let next: UInt16
        if buffer.count >= 2 {
            let start = buffer.startIndex
            next = UInt16(buffer[start]) | (UInt16(buffer[start + 1]) << 8)
        } else if let lone = buffer.first {
            next = UInt16(lone) << 8
        } else {
            next = 0
        }
        let lo = rotl16(next, lowBits) & mask16(lowBits)
        return UInt16(truncatingIfNeeded: (UInt32(hi) << lowBits) | UInt32(lo))
    }

    // MARK: - Arithmétique u16 du Rust (rotate_left, masques débordants)

    /// `UInt16.rotateLeft` — les décalages Swift piègent au-delà de 16,
    /// les masquants (`&<<`/`&>>`) reproduisent le Rust pour tout montant.
    private func rotl16(_ value: UInt16, _ amount: Int) -> UInt16 {
        (value &<< amount) | (value &>> (16 &- amount))
    }

    /// `(1 << bits) - 1` sur 16 bits ; à 16 le Rust passe par un `u32`
    /// tronqué — ici le cas est nommé.
    private func mask16(_ bits: Int) -> UInt16 {
        bits >= 16 ? .max : UInt16((1 << bits) - 1)
    }
}
