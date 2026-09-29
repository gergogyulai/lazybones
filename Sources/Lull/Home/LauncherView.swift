import SwiftUI

/// tvOS-style home screen: a full-bleed top shelf for the focused app over a grid of app icons,
/// with a top bar above for the clock and Settings. Focusing a lower row scrolls the shelf away
/// and leaves it as a blurred backdrop.
struct LauncherView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let apps = model.visible
            let shelf = model.settings.showShelf
            let layout = LauncherLayout(size: geo.size, columns: model.columns, shelf: shelf, count: apps.count,
                                        selected: model.selected, appFocused: !model.focus.onBar)
            let m = layout.metrics
            let barFocused = model.focus.onBar
            let audio = Set(model.backgroundAudio.map(\.id))

            ZStack(alignment: .topLeading) {
                if apps.isEmpty {
                    EmptyLauncher(unit: m.unit)
                } else {
                    let focused = apps[layout.selected]
                    let scrolled = layout.scrolled

                    if shelf {
                        ShelfArt(service: focused, size: geo.size, unit: m.unit)
                            .id(focused.id)
                            .transition(.opacity)
                            .blur(radius: scrolled ? 50 * m.unit : 0)
                            .overlay(Color.black.opacity(scrolled ? 0.55 : 0))
                            .ignoresSafeArea()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        // Always takes up the header's height, even with no shelf to fill it: modifiers
                        // on an empty group would silently vanish, and the grid would slide up.
                        ZStack(alignment: .bottomLeading) {
                            Color.clear
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
                                        AppIcon(service: apps[i], focused: i == layout.selected && !barFocused,
                                                move: model.navDirection, trigger: model.navTick, metrics: m,
                                                playing: audio.contains(apps[i].id))
                                            .zIndex(i == layout.selected ? 1 : 0)
                                            .onTapGesture { model.click(app: i) }
                                            .onHover { if $0 { model.hover(app: i) } }
                                    }
                                }
                                .zIndex(r == layout.row ? 1 : 0)
                            }
                        }
                    }
                    .padding(.horizontal, m.sidePadding)
                    .offset(y: layout.scrollOffset)
                }

                if model.settings.showHints {
                    Text("Clickpad to move · click to open · TV button for Home · press it twice for the app switcher · hold it for Control Center")
                        .font(.system(size: 17 * m.unit))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .padding(.leading, m.sidePadding)
                        .padding(.top, 52 * m.unit)
                        .frame(maxWidth: geo.size.width - 380 * m.unit, maxHeight: .infinity, alignment: .topLeading)
                }

                TopBar(unit: m.unit, focused: barFocused)
                    .padding(.trailing, m.sidePadding)
                    .padding(.top, 32 * m.unit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .animation(.easeInOut(duration: 0.45), value: apps.isEmpty ? "" : apps[layout.selected].id)
            .animation(.spring(duration: 0.5, bounce: 0.1), value: layout.row)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: barFocused)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.launcherFrame = $0 }
    }
}

/// The clock and Settings, above the apps. Up from the first row reaches Settings.
private struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let unit: CGFloat
    let focused: Bool

    var body: some View {
        HStack(spacing: 28 * unit) {
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 30 * unit, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 6 * unit)
            }
            Image(systemName: "gearshape.fill")
                .font(.system(size: 26 * unit, weight: .semibold))
                .foregroundStyle(focused ? .black : .white)
                .frame(width: 64 * unit, height: 64 * unit)
                .glassSurface(Circle(), tint: focused ? .white.opacity(0.92) : nil, interactive: true)
                .scaleEffect(focused ? 1.18 : 1)
                .contentShape(Circle())
                .onTapGesture { model.openSettingsScreen() }
                .onHover { if $0 { model.hoverBar() } }
                .accessibilityLabel("Settings")
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
            Text("Open Settings to show or add apps.")
                .font(.system(size: 24 * unit))
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
