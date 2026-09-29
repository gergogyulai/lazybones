import SwiftUI

/// The one window: the launcher or the open service, with the keyboard, HUDs and Control Center on top.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var controlCenter: ControlCenter
    @EnvironmentObject var keyboard: KeyboardController
    @EnvironmentObject var diagnostics: Diagnostics
    @EnvironmentObject var volume: VolumeController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let s = model.active, let wv = model.web.views[s.id] {
                WebContainer(webView: wv).id(s.id).ignoresSafeArea()
            } else {
                LauncherView()
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
            if controlCenter.isOpen {
                ControlCenterView(perform: model.perform)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.settingsRequests) { openSettings() }
    }
}
