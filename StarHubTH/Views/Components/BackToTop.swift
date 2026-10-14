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
/// s'écrit que quand le booléen change. Le premier rattachement écrit une
/// ligne au journal : sans `NSScrollView` trouvée, le bouton ne peut pas
/// apparaître, et le journal le dit.
enum BackToTop {
    /// L'id posé sur la tête de page, cible du retour.
    static let anchor = "back-to-top"
}

extension View {
    /// Sur la tête de page : `scrolledPast` passe à `true` quand son bas
    /// remonte au-dessus du haut de la zone visible.
    func backToTopMarker(scrolledPast: Binding<Bool>, log: @escaping (String) -> Void = { _ in }) -> some View {
        id(BackToTop.anchor)
            .background(ScrollPastWatcher(scrolledPast: scrolledPast, log: log))
    }
}

private struct ScrollPastWatcher: NSViewRepresentable {
    @Binding var scrolledPast: Bool
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
    }

    final class WatcherView: NSView {
        var onChange: ((Bool) -> Void)?
        var log: ((String) -> Void)?
        private var logged = false
        private var observed: NSView?

        /// Transparente à la souris : posée derrière la rangée d'ancres, elle
        /// ne doit jamais prendre un clic.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        private var token: NSObjectProtocol?
        private var last: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
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
        }
    }
}

/// Le bouton lui-même, à poser en `.overlay(alignment: .bottomTrailing)` du
/// `ScrollView`. Cible de 32 pt : le `.help` s'y affiche (piège des petits
/// glyphes), et le libellé reste lu par VoiceOver.
struct BackToTopButton: View {
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
