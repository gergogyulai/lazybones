import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppsSettings().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            LayoutSettings().tabItem { Label("Layout", systemImage: "rectangle.3.group") }
            SleepSettings().tabItem { Label("Sleep Mode", systemImage: "moon.zzz") }
            TVSettings().tabItem { Label("TV", systemImage: "tv") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 760, height: 520)
    }
}
