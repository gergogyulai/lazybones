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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            // Always there, fully transparent while an app is open, so it doesn't have to be built
            // (its shelf art is a big blur) at the moment an exit animation starts.
            LauncherView()
                .scaleEffect(model.zoomed ? 1.08 : 1)
                .opacity(model.zoomed ? 0 : 1)
                .allowsHitTesting(model.active == nil)
            ForEach(model.mounted) { s in
                if let wv = model.web.views[s.id] {
                    ServiceLayer(service: s, webView: wv)
                }
            }
            if keyboard.isVisible, let s = model.active {
                KeyboardView(accent: s.accent ?? s.color)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            VStack(alignment: .trailing, spacing: 12) {
                if let v = volume.hud {
                    VolumeHUDView(state: v).transition(.move(edge: .top).combined(with: .opacity))
                }
                if diagnostics.isVisible {
                    DebugOverlay(service: model.active)
                }
            }
            .padding(20)
            if switcher.isOpen {
                AppSwitcherView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
            if settingsScreen.isOpen {
                SettingsScreenView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
            if controlCenter.isOpen {
                ControlCenterView(perform: model.perform)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.settingsRequests) { openSettings() }
    }
}
