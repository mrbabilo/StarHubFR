import AppKit
import SwiftUI

/// Retour rapide en haut d'une page longue : un bouton flottant, en bas à
/// droite, qui n'apparaît qu'une fois la tête de page sortie de l'écran.
///
/// Cible macOS 14 : `onScrollGeometryChange` (macOS 15) n'existe pas. Une
/// première version — un `GeometryReader` qui remontait sa position par
/// `PreferenceKey` — n'affichait pas le bouton à l'écran (constat de
/// l'auteur, 2026-10-14 ; cause non établie). La tête de page porte donc une
/// vue AppKit qui écoute le défilement de son `NSScrollView`
/// (`boundsDidChangeNotification` du `contentView`) et compare les cadres en
/// coordonnées de fenêtre, quel que soit le sens des axes. L'état SwiftUI ne
/// s'écrit que quand le booléen change. Un défilement programmé
/// (`ScrollViewProxy.scrollTo`, les ancres) ne poste pas cette notification
/// (constat de l'auteur, 2026-10-14) : la page incrémente `recheck` après
/// chaque saut, et la vue remesure aussitôt puis une fois l'animation finie.
/// Le premier rattachement écrit une
/// ligne au journal : sans `NSScrollView` trouvée, le bouton ne peut pas
/// apparaître, et le journal le dit.
enum BackToTop {
    /// L'id posé sur la tête de page, cible du retour.
    static let anchor = "back-to-top"
}

extension View {
    /// Sur la tête de page : `scrolledPast` passe à `true` quand son bas
    /// remonte au-dessus du haut de la zone visible.
    func backToTopMarker(scrolledPast: Binding<Bool>, recheck: Int = 0,
                         log: @escaping (String) -> Void = { _ in }) -> some View {
        id(BackToTop.anchor)
            .background(ScrollPastWatcher(scrolledPast: scrolledPast, recheck: recheck, log: log))
    }
}

private struct ScrollPastWatcher: NSViewRepresentable {
    @Binding var scrolledPast: Bool
    let recheck: Int
    let log: (String) -> Void

    func makeNSView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.log = log
        view.onChange = { past in
            if past != scrolledPast { scrolledPast = past }
        }
        return view
    }

    func updateNSView(_ nsView: WatcherView, context: Context) {
        nsView.onChange = { past in
            if past != scrolledPast { scrolledPast = past }
        }
        guard recheck != nsView.recheck else { return }
        nsView.recheck = recheck
        nsView.evaluateSoon()
    }

    final class WatcherView: NSView {
        var onChange: ((Bool) -> Void)?
        var log: ((String) -> Void)?
        var recheck = 0
        private var logged = false
        private var observed: NSView?

        /// Transparente à la souris : posée derrière la rangée d'ancres, elle
        /// ne doit jamais prendre un clic.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        private var token: NSObjectProtocol?
        /// Filet : un saut programmé d'une page (`scrollTo` de ses propres
        /// ancres) ne poste pas la notification ; on remesure deux fois par
        /// seconde tant que la vue est dans une fenêtre. Mesure de deux cadres,
        /// état écrit seulement au changement.
        private var timer: Timer?
        private var last: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attach()
        }

        private func attach() {
            if window != nil, !logged {
                logged = true
                log?(enclosingScrollView == nil ? "Retour en haut : NSScrollView introuvable, bouton inactif."
                                                : "Retour en haut : NSScrollView trouvée.")
            }
            guard let clip = enclosingScrollView?.contentView else { return detach() }
            guard clip !== observed else { return evaluate() }
            detach()
            observed = clip
            clip.postsBoundsChangedNotifications = true
            token = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            evaluate()
        }

        private func detach() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            observed = nil
        }

        /// Après un saut programmé : maintenant, puis l'animation finie.
        func evaluateSoon() {
            evaluate()
            Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }   // tâche annulée
                self?.evaluate()
            }
        }

        /// Le bas de la tête de page est-il au-dessus du haut visible ? En
        /// coordonnées de fenêtre (origine en bas) : son `minY` dépasse le
        /// `maxY` de la zone visible.
        private func evaluate() {
            guard window != nil, let scroll = enclosingScrollView else { return }
            let marker = convert(bounds, to: nil)
            let visible = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            let past = marker.minY >= visible.maxY
            guard past != last else { return }
            last = past
            onChange?(past)
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            timer?.invalidate()
        }
    }
}

/// Un `ScrollView` vertical de page avec son retour en haut : remplace
/// `ScrollView { … }` mot pour mot. Le bouton apparaît au-delà de
/// `threshold` points défilés — jamais sur une page qui ne défile pas assez.
/// Une marge basse de contenu lui laisse la place de ne rien couvrir.
struct BackToTopScrollView<Content: View>: View {
    @ObservedObject var localization: LocalizationStore
    var showsIndicators = true
    var threshold: CGFloat = 300
    @ViewBuilder let content: Content
    @State private var scrolledPast = false
    @State private var recheck = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ localization: LocalizationStore, showsIndicators: Bool = true, threshold: CGFloat = 300,
         @ViewBuilder content: () -> Content) {
        self.localization = localization
        self.showsIndicators = showsIndicators
        self.threshold = threshold
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                content.overlay(alignment: .top) {
                    Color.clear.frame(height: threshold).allowsHitTesting(false)
                        .backToTopMarker(scrolledPast: $scrolledPast, recheck: recheck)
                }
            }
            .contentMargins(.bottom, BackToTopButton.reservedHeight, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                if scrolledPast {
                    BackToTopButton(title: localization.L(L10n.Main.backToTop)) {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo(BackToTop.anchor, anchor: .top)
                        }
                        recheck += 1
                    }
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: scrolledPast)
        }
    }
}

/// Le bouton lui-même, à poser en `.overlay(alignment: .bottomTrailing)` du
/// `ScrollView`. Cible de 32 pt : le `.help` s'y affiche (piège des petits
/// glyphes), et le libellé reste lu par VoiceOver.
struct BackToTopButton: View {
    /// Bouton (32) et sa marge (`Spacing.lg` ×2) : la place à laisser sous le contenu.
    static let reservedHeight: CGFloat = 32 + 2 * AppDesign.Spacing.lg
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(AppDesign.Font.body(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 1))
        .shadow(color: .black.opacity(AppDesign.Opacity.medium), radius: 3, y: 1)
        .help(title)
        .accessibilityLabel(title)
        .clickableCursor()
        .padding(AppDesign.Spacing.lg)
    }
}
