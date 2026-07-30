import SwiftUI
import AppKit

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
        showMainWindow()

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
        guard let window = mainAppWindow() else { return }
        mainWindow = window
        window.orderOut(nil)

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
                Text("StarHubFR")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
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
                .fill(Color.black.opacity(0.92))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.L(L10n.Main.launching))
    }

    /// Cover art bundled as a resource by `build_app.py`.
    private static let backgroundImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "nexus_cover_final", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
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
