import SwiftUI

/// tvOS-style home screen: a full-bleed top shelf for the focused app over a grid of app icons.
/// Focusing a lower row scrolls the shelf away and leaves it as a blurred backdrop.
struct LauncherView: View {
    @EnvironmentObject var model: AppModel
    /// Direction of the last focus move, used to tilt the newly focused icon like tvOS parallax.
    @State private var move = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            let apps = model.visible
            let shelf = model.settings.showShelf
            let m = Metrics(size: geo.size, columns: model.columns, shelf: shelf)
            if apps.isEmpty {
                EmptyLauncher(unit: m.unit)
            } else {
                let focused = apps[min(model.selected, apps.count - 1)]
                let row = model.selected / model.columns
                let scrolled = shelf ? row > 0 : m.rowTop(row) + m.tileHeight + m.rowSpacing > geo.size.height

                ZStack(alignment: .topLeading) {
                    if shelf {
                        ShelfArt(service: focused, size: geo.size, unit: m.unit)
                            .id(focused.id)
                            .transition(.opacity)
                            .blur(radius: scrolled ? 50 * m.unit : 0)
                            .overlay(Color.black.opacity(scrolled ? 0.55 : 0))
                            .ignoresSafeArea()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if shelf {
                                ShelfCaption(service: focused, unit: m.unit)
                                    .id(focused.id)
                                    .transition(.opacity.combined(with: .offset(y: 12 * m.unit)))
                            }
                        }
                        .frame(height: m.headerHeight, alignment: .bottomLeading)
                        .padding(.bottom, m.captionGap)
                        .opacity(scrolled ? 0 : 1)

                        VStack(alignment: .leading, spacing: m.rowSpacing) {
                            ForEach(0..<m.rows(apps.count), id: \.self) { r in
                                HStack(spacing: m.gap) {
                                    ForEach(r * m.columns..<min((r + 1) * m.columns, apps.count), id: \.self) { i in
                                        AppIcon(service: apps[i], focused: i == model.selected,
                                                move: move, trigger: model.selected, metrics: m)
                                            .zIndex(i == model.selected ? 1 : 0)
                                            .onTapGesture { model.selected = i; model.open(apps[i]) }
                                            .onHover { if $0 { model.selected = i } }
                                    }
                                }
                                .zIndex(r == row ? 1 : 0)
                            }
                        }
                    }
                    .padding(.horizontal, m.sidePadding)
                    .offset(y: scrolled ? m.scrolledRowTop - m.rowTop(row) : 0)

                    if model.settings.showHints {
                        Text("Clickpad to move · click to open · TV button for home · hold TV or press Power for Control Center · Siri toggles debug · ⌘, for settings")
                            .font(.system(size: 17 * m.unit))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, m.sidePadding)
                            .padding(.top, 40 * m.unit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .animation(.easeInOut(duration: 0.45), value: focused.id)
                .animation(.spring(duration: 0.5, bounce: 0.1), value: row)
            }
        }
        .onChange(of: model.selected) { old, new in
            let c = model.columns
            move = CGSize(width: (new % c - old % c).signum(), height: (new / c - old / c).signum())
        }
    }
}

struct EmptyLauncher: View {
    let unit: CGFloat

    var body: some View {
        VStack(spacing: 16 * unit) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 72 * unit, weight: .light))
            Text("No apps on the Home Screen")
                .font(.system(size: 40 * unit, weight: .bold, design: .rounded))
            Text("Open Settings (⌘,) to show or add apps.")
                .font(.system(size: 24 * unit))
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
