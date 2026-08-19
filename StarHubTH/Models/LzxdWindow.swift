import Foundation

/// Taille de la fenêtre coulissante LZX — translittération de `window.rs`
/// de lzxd v0.2.6 (Lonami, MIT OR Apache-2.0), restreinte aux deux tailles
/// utiles ici (le `.xnb` du jeu décode en `kb64` ; `kb32` couvre les tests).
/// Le Rust expose 11 tailles ; n'en porter que deux évite du code mort —
/// `positionSlots` garde les valeurs exactes du Rust pour chacune.
public enum LzxdWindowSize {
    /// 32 Kio (`0x8000` dans le Rust).
    case kb32
    /// 64 Kio (`0x1_0000`) — la taille des `.xnb` de Stardew Valley.
    case kb64

    /// Taille du tampon, en octets.
    public var byteCount: Int {
        switch self {
        case .kb32: 32 * 1024
        case .kb64: 64 * 1024
        }
    }

    /// Nombre de subdivisions de fenêtre — détermine la taille de l'arbre
    /// principal (256 + 8 × slots). Valeurs mesurées de `window.rs`.
    public var positionSlots: Int {
        switch self {
        case .kb32: 30
        case .kb64: 32
        }
    }

    /// `MAX_CHUNK_SIZE` du Rust : le plafond d'un morceau XNB et d'une vue
    /// (`past_view` refuse au-delà).
    static let maxChunkSize = 32 * 1024

    func makeWindow() -> LzxdWindow {
        LzxdWindow(size: byteCount)
    }
}

/// Fenêtre coulissante LZX — translittération de `window.rs` de lzxd v0.2.6
/// (Lonami — https://github.com/Lonami/lzxd, commit `4f477bd`, MIT OR
/// Apache-2.0). Le Rust est la vérité : en cas de divergence, le Swift a tort.
///
/// Le tampon est **intégralement mis à zéro** à la création (comme le
/// `vec![0; size]` du Rust) : une lecture de match avant toute écriture voit
/// des zéros — c'est ce qu'exige la spec XMem, pas un détail d'implémentation.
///
/// Choix de portage : `copyFromSelf` copie toujours octet par octet. Le Rust
/// a un chemin rapide par blocs, mais uniquement quand source et destination
/// ne se chevauchent pas (`length <= offset`) — le résultat est identique, et
/// la copie par blocs sur un chevauchement écraserait la source en cours de
/// lecture (la répétition RLE d'un flux réel).
struct LzxdWindow {
    enum Error: Swift.Error, Equatable {
        case windowTooSmall
    }

    /// Position d'écriture suivante (`pos` dans le Rust).
    private var pos: Int
    private var buffer: [UInt8]

    fileprivate init(size: Int) {
        // Le Rust asserte ces deux invariants : la fenêtre porte au moins un
        // morceau entier, et son masque suppose une puissance de deux.
        precondition(size >= LzxdWindowSize.maxChunkSize,
                     "la fenêtre doit porter au moins un morceau (MAX_CHUNK_SIZE)")
        precondition(size.nonzeroBitCount == 1, "la taille de fenêtre doit être une puissance de deux")
        buffer = [UInt8](repeating: 0, count: size)
        pos = 0
    }

    // MARK: - Écriture (window.rs)

    mutating func push(_ value: UInt8) {
        buffer[pos] = value
        advance(1)
    }

    /// Copie LZ77 depuis la fenêtre elle-même : `offset` = 1 signifie « le
    /// dernier octet écrit ». Le chevauchement est légal et voulu.
    mutating func copyFromSelf(offset: Int, length: Int) {
        let mask = buffer.count - 1   // puissance de deux, cf. init
        for i in 0..<length {
            let dst = (pos + i) & mask
            let src = (buffer.count + pos + i - offset) & mask
            buffer[dst] = buffer[src]
        }
        advance(length)
    }

    /// Bloc verbatim : `length` octets lus bruts depuis le bitstream (aligné).
    mutating func copyFromBitstream(_ stream: inout LzxdBitstream, length: Int) throws {
        if length > buffer.count { throw Error.windowTooSmall }

        if pos + length > buffer.count {
            // Faire de la place contiguë en fin de tampon : déplacer le début
            // vers… le début (le Rust déplace la fin écrasée d'autant —
            // inutile de la sauver, elle sera réécrite).
            let shift = pos + length - buffer.count
            pos -= shift
            let tail = Array(buffer[shift...])
            buffer.replaceSubrange(0..<(buffer.count - shift), with: tail)
        }

        var chunk = [UInt8](repeating: 0, count: length)
        try stream.readRaw(into: &chunk)
        buffer.replaceSubrange(pos..<(pos + length), with: chunk)
        advance(length)
    }

    /// Les `length` derniers octets écrits, dans l'ordre — le Rust rend
    /// `&mut [u8]` en fin de tampon ; ici une `ArraySlice` **valide jusqu'au
    /// prochain appel mutateur** de la fenêtre.
    ///
    /// Plafonné à `MAX_CHUNK_SIZE`, comme `past_view` du Rust.
    mutating func pastView(_ length: Int) -> ArraySlice<UInt8> {
        precondition(length <= LzxdWindowSize.maxChunkSize,
                     "pastView: MAX_CHUNK_SIZE au plus (past_view du Rust)")
        precondition(length <= buffer.count, "pastView: plus grand que la fenêtre")

        // Lire derrière soi : si la vue déborde de `pos`, faire tourner le
        // tampon pour qu'elle soit contiguë. `pos == 0` signifie « au bout » :
        // rien à tourner, la vue se détache de la fin du tampon.
        if pos != 0 && length > pos {
            let shift = length - pos
            advance(shift)
            let head = Array(buffer[0..<(buffer.count - shift)])
            let tail = Array(buffer[(buffer.count - shift)...])
            buffer.replaceSubrange(shift..., with: head)
            buffer.replaceSubrange(0..<shift, with: tail)
        }

        let end = pos == 0 ? buffer.count : pos
        return buffer[(end - length)..<end]
    }

    /// `advance` du Rust : un seul retrait suffit — chaque appelant avance
    /// d'au plus une fenêtre.
    private mutating func advance(_ delta: Int) {
        pos += delta
        if pos >= buffer.count {
            pos -= buffer.count
        }
    }
}
