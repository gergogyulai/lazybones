import AppKit
import SwiftUI

@main
struct LazybonesApp: App {
    @StateObject private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
            print("usage: Lazybones [options]\n\n\(LaunchOptions.usage)")
            exit(0)
        }
    }

    var body: some Scene {
        Window("Lazybones", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.controlCenter)
                .environmentObject(model.sleepTimer)
                .environmentObject(model.switcher)
                .environmentObject(model.settingsScreen)
                .environmentObject(model.tv)
                .environmentObject(model.keyboard)
                .environmentObject(model.diagnostics)
                .environmentObject(model.extensions.adBlock)
                .environmentObject(model.volume)
                .environmentObject(model.parallax)
                .frame(minWidth: 960, minHeight: 540)
                .onAppear(perform: enterFullScreenIfWanted)
        }
        .commands {
            CommandMenu("Lazybones") {
                Button("Home") { model.homePressed() }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("App Switcher") { model.openSwitcher() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Control Center") { model.toggleControlCenter() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Sleep Mode") { model.toggleSleepMode() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Sleep Timer") { model.toggleSleepTimer() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Launcher Settings") { model.openSettingsScreen() }.keyboardShortcut(",", modifiers: [.command, .option])
                Button("Toggle Debug") { model.diagnostics.toggle() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Debug Window") { model.openDebugWindow() }.keyboardShortcut("i", modifiers: [.command, .option])
                Button("Remote Simulator") { model.simulator.toggle() }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Reload") { model.reload() }.keyboardShortcut("r")
            }
            CommandGroup(replacing: .appInfo) { AboutButton() }
            // ⌘, opens the Settings window below rather than SwiftUI's preferences-style one.
            CommandGroup(replacing: .appSettings) { OpenSettingsButton() }
        }

        // A full window rather than a `Settings` scene, so it gets what System Settings has: a
        // unified toolbar with back and forward, the sidebar floating as glass, and resizing.
        Window("Lazybones Settings", id: SettingsView.windowID) {
            SettingsView().environmentObject(model).environmentObject(model.tv)
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 760)
        .defaultPosition(.center)
        .commandsRemoved()

        // Sized to its content, with only a close button, like the standard About panel.
        Window("About Lazybones", id: AboutView.windowID) {
            AboutView().windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("uBlock Origin Lite Settings", id: AdBlockerSettingsWindow.windowID) {
            AdBlockerSettingsWindow(extensions: model.extensions)
        }
        .defaultSize(width: 900, height: 700)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Window("Lazybones Debug", id: DebugWindow.windowID) {
            DebugWindow().environmentObject(model).environmentObject(model.diagnostics)
        }
        .defaultSize(width: 900, height: 640)
        .commandsRemoved()
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
