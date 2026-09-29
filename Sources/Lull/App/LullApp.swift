import AppKit
import SwiftUI

@main
struct LullApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Lull", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.controlCenter)
                .environmentObject(model.tv)
                .environmentObject(model.keyboard)
                .environmentObject(model.diagnostics)
                .environmentObject(model.volume)
                .frame(minWidth: 960, minHeight: 540)
                .onAppear(perform: enterFullScreenIfWanted)
        }
        .commands {
            CommandMenu("Lull") {
                Button("Home") { model.goHome() }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Control Center") { model.toggleControlCenter() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Toggle Debug") { model.diagnostics.toggle() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Remote Simulator") { model.simulator.toggle() }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Reload") { model.reload() }.keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView().environmentObject(model).environmentObject(model.tv)
        }
    }

    private func enterFullScreenIfWanted() {
        guard model.startsFullScreen else { return }
        DispatchQueue.main.async {
            if let w = NSApp.windows.first(where: \.isVisible), !w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
            }
        }
    }
}
