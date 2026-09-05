import SwiftUI
import AppKit
import CoreImage

/// The launch splash, shown in its own borderless window while the main window
/// stays hidden.
///
/// Previously the splash was an overlay painted inside the main window, so the
/// user saw the 900×600 frame, its title bar and its chrome before anything was
/// loaded — and the native menus had to be torn down (`NSApp.mainMenu = nil`)
/// to stop Cmd+W acting on a half-built UI. With a separate window the main
/// window simply isn't on screen until the app is ready.
@MainActor
final class LaunchSplashController {
    static let shared = LaunchSplashController()
    private init() {}

    private var panel: NSPanel?
    /// Set once loading completes, so a late `show()` becomes a no-op.
    private var finished = false
    /// Main window we hid at startup, restored once loading finishes.
    private weak var mainWindow: NSWindow?

    /// Ce qu'il faut faire **une fois la fenêtre principale à l'écran**, quel
    /// que soit le chemin qui l'y a mise (X65).
    ///
    /// Trois chemins révèlent la fenêtre : la fin de chargement ordinaire, un
    /// lancement déjà terminé quand la vue paraît, et le filet de sécurité des
    /// 30 secondes. Les deux premiers délivraient à la main les liens `nxm://`
    /// mis en attente ; le troisième, non — un lancement à froid déclenché par
    /// « Mod Manager Download » et resté bloqué au-delà de 30 s rendait la
    /// fenêtre puis ne téléchargeait jamais rien, sans un mot. La règle vit
    /// désormais ici, en un seul exemplaire.
    var onReveal: (() -> Void)?

    /// Hides the main window the moment AppKit creates it, before it is ever
    /// drawn. Called from `applicationWillFinishLaunching`.
    ///
    /// Ordering the window out from SwiftUI's `.onAppear` is too late — it has
    /// already been presented, so it flashes for a frame. Observing
    /// `didUpdateNotification` catches the window as soon as it exists.
    func claimMainWindowBeforeItAppears() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { [weak self] note in
            // `queue: .main` livre l'observateur sur le MainActor, mais le bloc
            // est typé `@Sendable` et le compilateur ne le sait pas. On le lui
            // affirme via `assumeIsolated` (vérifié au runtime) plutôt que de
            // différer : un `orderOut` retardé d'un cycle laisserait la fenêtre
            // flasher avant d'être masquée. Aucun changement de comportement.
            MainActor.assumeIsolated {
                guard let self, !self.finished,
                      let window = note.object as? NSWindow,
                      window !== self.panel,
                      !(window is NSPanel),
                      window.styleMask.contains(.titled) else { return }
                // Ne capturer que la **première** fenêtre titrée, et ne plus
                // jamais réviser ce choix. Le code réassignait `mainWindow` à
                // chaque notification : toute autre fenêtre titrée paraissant
                // avant `finish()` — une feuille d'installation ouverte par un
                // lien `nxm://`, par exemple — devenait « la fenêtre
                // principale ». `showMainWindow()` révélait alors celle-là, et
                // la vraie restait masquée, l'app inatteignable.
                if self.mainWindow == nil { self.mainWindow = window }
                guard window === self.mainWindow else { return }
                if window.isVisible { window.orderOut(nil) }
            }
        }
    }

    private var observer: NSObjectProtocol?

    /// Shows the splash and hides the main window until `finish()` is called.
    ///
    /// The main window is found by identifier rather than assumed to be
    /// `NSApp.windows.first`: the panel itself is a window too, and at launch
    /// AppKit may report them in either order.
    func show(vm: StarHubTHViewModel) {
        // Loading may already have finished before this ran — don't put a
        // splash up that nothing will ever take down.
        guard panel == nil, !finished else { return }

        let hosting = NSHostingView(rootView: LaunchSplashView(vm: vm))
        let size = NSSize(width: 720, height: 560)
        // Not `.nonactivatingPanel`: at launch the app has no active window
        // yet, and a non-activating panel then never comes forward.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        // Not `.transient`: that hides the panel whenever the app isn't
        // frontmost, which during launch means it may never be seen.
        panel.collectionBehavior = [.ignoresCycle]
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        hideMainWindow()
    }

    /// Dismisses the splash and reveals the main window.
    ///
    /// Safe to call before `show()` (a launch fast enough to finish first) and
    /// safe to call twice: revealing the window is the part that must always
    /// happen, so it runs unconditionally.
    func finish() {
        finished = true
        // Must come first: the observer hides the main window on sight, so
        // leaving it attached would fight the reveal below.
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        showMainWindow()
        // Avant le `guard` : un lancement assez rapide pour finir avant
        // `show()` n'a pas de panneau, et sortir ici priverait ce chemin-là de
        // la livraison — une quatrième asymétrie à la place des trois qu'on
        // vient de réduire. `makeKeyAndOrderFront` a déjà eu lieu (l'animation
        // qui suit ne fait que monter l'opacité) : la fenêtre est à l'écran,
        // ce qu'une feuille d'installation demande pour s'y attacher.
        onReveal?()

        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: - Main window

    /// The app's real window, as opposed to our splash panel or any of the
    /// auxiliary windows AppKit keeps around (status items, tooltips…).
    /// Identified by being a titled, non-panel window that isn't ours, since
    /// SwiftUI's `Window(id:)` doesn't reliably surface that id on NSWindow.
    private func mainAppWindow() -> NSWindow? {
        NSApp.windows.first {
            $0 !== panel
                && !($0 is NSPanel)
                && $0.styleMask.contains(.titled)
                && $0.contentView != nil
        }
    }

    private func hideMainWindow() {
        // Usually already done by the observer set up in
        // `claimMainWindowBeforeItAppears`; this covers the case where the
        // window appeared before the observer was attached.
        if let window = mainWindow ?? mainAppWindow() {
            mainWindow = window
            if window.isVisible { window.orderOut(nil) }
        }

        // Safety net: if loading never completes (or `finish()` is missed), the
        // app must not be left with no visible window at all. Revealing early
        // is far less bad than an app the user can't get to.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.panel != nil else { return }
            self.finish()
        }
    }

    private func showMainWindow() {
        let window = mainWindow ?? mainAppWindow()
        guard let window else { return }
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }
}

/// Splash contents: cover artwork, app identity, and the creeping progress bar.
/// Draws its own rounded background since the hosting panel is borderless.
struct LaunchSplashView: View {
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Cover artwork, contained — preserving the source's 16:9 ratio.
            Group {
                if let bg = Self.backgroundImage {
                    Image(nsImage: bg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 640, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 640, height: 360)
                }
            }

            VStack(spacing: 4) {
                // Version alongside the wordmark rather than on its own line:
                // the splash is compact, and a third line would push the
                // progress bar down for a detail that belongs to the title.
                // Baseline-aligned so it sits with the name, not the cap height.
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("StarHubFR")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("v\(Self.appVersion)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text(vm.L(L10n.Main.launching))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            LaunchProgressBar(vm: vm)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                // A gradient rather than a flat fill: the artwork has depth, and
                // a single tone behind it reads as a printed panel.
                .fill(
                    LinearGradient(
                        colors: [Self.backdrop.opacity(0.97), Self.backdrop.opacity(1.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.L(L10n.Main.launching))
    }

    /// Cover art bundled as a resource by `build_app.py`.
    /// Version affichée, lue dans le bundle pour rester juste après chaque
    /// release (même source que l'écran d'accueil). Le repli ne sert qu'aux
    /// exécutions hors bundle.
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static let backgroundImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "nexus_cover_final", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Backdrop derived from the artwork itself rather than a hardcoded colour,
    /// so the splash stays harmonious if the cover is ever replaced.
    ///
    /// A plain black panel read as a hole punched behind the image; sampling the
    /// cover's dominant tone and darkening it keeps enough contrast for white
    /// text while letting the panel feel like part of the same picture.
    private static let backdrop: Color = {
        guard let image = backgroundImage, let tone = image.dominantColor() else {
            return Color.black.opacity(0.92)
        }
        return Color(nsColor: tone.darkened(to: 0.16))
    }()
}

private extension NSImage {
    /// Average colour of the image, used to tint the splash backdrop.
    ///
    /// Averaging via a 1×1 downscale is enough here: the cover is a single
    /// coherent scene, so its mean lands on the tone that dominates it. A
    /// histogram/clustering approach would be more accurate on busy artwork but
    /// is far more machinery than a backdrop tint warrants.
    func dominantColor() -> NSColor? {
        guard let tiff = tiffRepresentation,
              let source = CIImage(data: tiff) else { return nil }

        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)

        return NSColor(srgbRed: CGFloat(pixel[0]) / 255,
                       green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255,
                       alpha: 1)
    }
}

private extension NSColor {
    /// Same hue, forced to a low brightness — keeps the tint recognizable while
    /// staying dark enough for white text to pass contrast.
    func darkened(to brightness: CGFloat) -> NSColor {
        guard let hsb = usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Saturation is nudged up a little: averaging washes colours out, and a
        // fully desaturated backdrop would just look grey.
        return NSColor(hue: h, saturation: min(1, s * 1.3), brightness: brightness, alpha: 1)
    }
}

/// Determinate bar that CREEPS toward its target instead of snapping.
///
/// Launch progress is published as a handful of discrete weights (0.05 → 0.15 →
/// 0.25 → …) with real wall-clock gaps between them (registry decode,
/// folder-repair sweep). A bar that jumps between those weights looks like it
/// teleports, then freezes during each gap. `displayed` chases `target` on a
/// timer — always moving, even mid-gap — so the splash never looks stuck.
struct LaunchProgressBar: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var displayed: Double = 0

    // Static → one underlying timer, never stacked across re-renders.
    private static let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var target: Double {
        if let scan = vm.scanProgress, scan.total > 0 {
            let span = StarHubTHViewModel.launchScanProgressEnd - StarHubTHViewModel.launchScanProgressStart
            let ratio = Double(scan.done) / Double(scan.total)
            return StarHubTHViewModel.launchScanProgressStart + span * ratio
        }
        return vm.launchProgress
    }

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: displayed, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(width: 420)

            Text(caption)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
        }
        .onReceive(Self.ticker) { _ in
            let goal = target
            guard displayed < goal else { return }
            // Ease toward the goal: fast when far, slow when close, so the bar
            // keeps moving through the gaps without ever overshooting.
            displayed += max(0.002, (goal - displayed) * 0.08)
        }
    }

    private var caption: String {
        if let scan = vm.scanProgress, scan.total > 0 {
            return "\(scan.currentName)  (\(scan.done)/\(scan.total))"
        }
        return vm.launchStep.isEmpty ? vm.L(L10n.Main.launching) : vm.launchStep
    }
}
