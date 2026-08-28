import SwiftUI

private final class AsyncImageCache {
    /// Borné : la vitrine « Découvrir » peut demander des centaines de
    /// vignettes en déroulant trois sections, et un `NSCache` sans limite ne
    /// rend la mémoire que sous pression du système. Le coût est le poids réel
    /// des pixels, pas le nombre d'images — une capture de fiche pèse cent
    /// fois une vignette.
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    static func nsImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    static func setNSImage(_ image: NSImage, for url: URL) {
        // 4 octets par pixel : l'ordre de grandeur suffit à faire le tri entre
        // une vignette et une capture pleine page.
        let pixels = Int(image.size.width * image.size.height)
        cache.setObject(image, forKey: url as NSURL, cost: max(1, pixels * 4))
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: Image?
    @State private var loadError: Error?

    var body: some View {
        Group {
            if let image = image {
                image.resizable().scaledToFill()
            } else if loadError != nil {
                Color.clear.frame(height: 0)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        // Réinitialise l'état à chaque chargement : sans quoi l'image du mod
        // précédent restait affichée si la nouvelle URL échouait (seul
        // loadError était mis, et `if let image` montrait l'ancienne). La
        // vérif de cache synchrone juste après évite tout clignotement.
        image = nil
        loadError = nil
        guard let url = url else { return }

        if let cached = AsyncImageCache.nsImage(for: url) {
            image = Image(nsImage: cached)
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let nsImage = NSImage(data: data) {
                AsyncImageCache.setNSImage(nsImage, for: url)
                image = Image(nsImage: nsImage)
            }
        } catch {
            loadError = error
        }
    }
}
