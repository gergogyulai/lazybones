import SwiftUI

/// The one window: the launcher, or the open service growing out of it, with the keyboard, HUDs,
/// app switcher, settings and Control Center on top.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controlCenter: ControlCenter
    @EnvironmentObject var switcher: AppSwitcher
    @EnvironmentObject var settingsScreen: SettingsScreen
    @EnvironmentObject var keyboard: KeyboardController
    @EnvironmentObject var diagnostics: Diagnostics
    @EnvironmentObject var volume: VolumeController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The window's width, for sizing the volume display like the rest of the interface.
    @State private var width: CGFloat = 1920

    var body: some View {
        // A screen that takes over (Settings, the app switcher) pushes whatever was showing back,
        // so it reads as a layer above it rather than a page replacing it.
        let receded = settingsScreen.isOpen || switcher.isOpen
        // Screens settle into place from just in front; with Reduce Motion they only fade.
        let screenTransition: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.05))

        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZStack {
                // Always there, fully transparent while an app is open, so it doesn't have to be
                // built (its shelf art is a big blur) at the moment an exit animation starts. It
                // moves toward you as an app grows out of it, and back as the app returns.
                LauncherView()
                    .scaleEffect(model.zoomed && !reduceMotion ? 1.08 : 1)
                    .opacity(model.zoomed ? 0 : 1)
                    .allowsHitTesting(model.active == nil)
                ForEach(model.mounted) { s in
                    if let wv = model.web.views[s.id] {
                        ServiceLayer(service: s, webView: wv)
                    }
                }
            }
            .scaleEffect(receded && !reduceMotion ? 0.96 : 1)
            if keyboard.isVisible, let s = model.active {
                KeyboardView(accent: s.accent ?? s.color, showsHints: model.settings.showHints)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            VStack(alignment: .trailing, spacing: 12) {
                if let v = volume.hud {
                    let u = max(width / 1920, 0.5)
                    VolumeHUDView(state: v, u: u)
                        .padding([.top, .trailing], 28 * u)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if diagnostics.isVisible {
                    DebugOverlay(service: model.active)
                }
            }
            .padding(20)
            if switcher.isOpen {
                AppSwitcherView()
                    .transition(screenTransition)
            }
            if settingsScreen.isOpen {
                SettingsScreenView()
                    .transition(screenTransition)
            }
            if controlCenter.isOpen {
                ControlCenterView(perform: model.perform, presses: model.presses)
            }
            if case .pairing(let pin) = model.phoneStatus {
                PhonePairingView(name: model.settings.phoneRemoteIdentity?.name ?? "Lazybones", pin: pin,
                                 u: max(width / 1920, 0.5))
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: model.settingsRequests) { openWindow(id: SettingsView.windowID) }
        .onChange(of: model.debugWindowRequests) { openWindow(id: DebugWindow.windowID) }
        .onChange(of: model.adBlockerSettingsRequests) { openWindow(id: AdBlockerSettingsWindow.windowID) }
    }
}
