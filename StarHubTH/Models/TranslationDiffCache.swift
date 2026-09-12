import Foundation

/// Les rangées de diff d'un mod, gardées le temps qu'un dossier `i18n` ne
/// change pas (F7).
///
/// **Ce qu'il achète, mesuré le 2026-09-12 sur le parc réel** : le calcul des
/// rangées coûte 1 205 à 2 569 ms selon le mod (six passes caractère par
/// caractère sur le même fichier — voir ROADMAP F7), et l'empreinte qui dit
/// s'il faut le refaire coûte **0,2 à 0,4 ms**.
///
/// ⚠️ **Il ne garde que `diffRows`, pas le résultat de `translationDiff`.** Ce
/// dernier applique la référence (baseline), en **adopte** et en **réancre**
/// des clés, et écrit l'index des clés obsolètes — court-circuiter tout ça
/// figerait les clés à leur état du jour, et une traduction retouchée ne
/// pourrait plus jamais être dite obsolète. Ce qui est gardé ici ne dépend
/// que des fichiers du mod, et rien d'autre.
///
/// ⚠️ **Une empreinte absente n'est pas une empreinte vide.** Sans fichier de
/// traduction, `TranslationStamp.of` rend `nil` — et une entrée rangée sous
/// cette absence vaudrait pour **n'importe quel** autre mod sans traduction.
/// Un `nil` ne se lit ni ne s'écrit donc jamais.
///
/// La clé est le **chemin du dossier**, non le nom logique du mod : un mod en
/// pause vit dans un dossier préfixé par un point, et `X` actif comme `.X` en
/// pause portent le même `folderName`. Les indexer ensemble servirait les
/// rangées de l'un pour l'autre.
/// `@unchecked Sendable` : l'état est protégé par `lock`, et la closure
/// détachée de `translationDiff` le capture.
final class TranslationDiffCache: @unchecked Sendable {

    private struct Entry {
        let stamp: TranslationStamp
        let rows: [TranslationCoverage.DiffRow]
    }

    /// Trois entrées : une entrée pèse **1,1 à 2,3 Mo** de chaînes sur le parc
    /// réel (10 597 rangées pour 1,5 Mo), et le geste à couvrir est d'ouvrir
    /// une fiche, la fermer, y revenir — pas de parcourir le parc.
    private let capacity: Int
    private var entries: [String: Entry] = [:]
    /// Du plus ancien accès au plus récent. Éviction par la tête.
    private var order: [String] = []
    private let lock = NSLock()

    init(capacity: Int = 3) {
        self.capacity = max(1, capacity)
    }

    /// Les rangées gardées pour ce dossier, si l'empreinte n'a pas bougé.
    func rows(forModAt directory: URL,
                     stamp: TranslationStamp?) -> [TranslationCoverage.DiffRow]? {
        guard let stamp else { return nil }
        let key = directory.path
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.stamp == stamp else { return nil }
        touch(key)
        return entry.rows
    }

    /// Garde ces rangées sous cette empreinte.
    func store(_ rows: [TranslationCoverage.DiffRow],
                      forModAt directory: URL,
                      stamp: TranslationStamp?) {
        guard let stamp else { return }
        let key = directory.path
        lock.lock()
        defer { lock.unlock() }
        entries[key] = Entry(stamp: stamp, rows: rows)
        touch(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    /// Appelé sous le verrou.
    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
