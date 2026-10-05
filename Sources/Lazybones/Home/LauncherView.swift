import SwiftUI

/// tvOS-style home screen: a full-bleed top shelf for the focused app over a grid of app icons,
/// with a top bar above for the clock and Settings. Focusing a lower row scrolls the shelf away
/// and leaves it as a blurred backdrop.
struct LauncherView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The app the top shelf shows. It follows focus once focus rests, so a quick swipe across a
    /// row doesn't flash every app's artwork on the way.
    @State private var shelfID: String?

    /// How long focus has to rest on an app before the shelf changes to it.
    private static let shelfSettle = Duration.milliseconds(180)

    var body: some View {
        GeometryReader { geo in
            let apps = model.visible
            let settings = model.settings
            let shelf = settings.showShelf
            let motion = settings.homeMotion
            let layout = LauncherLayout(size: geo.size, columns: model.columns, shelf: shelf, count: apps.count,
                                        selected: model.selected, appFocused: !model.focus.onBar,
                                        focusScale: settings.focusSize.scale)
            let m = layout.metrics
            let barFocused = model.focus.onBar
            let audio = Set(model.backgroundAudio.map(\.id))
            let nav = model.navDirection

            ZStack(alignment: .topLeading) {
                if apps.isEmpty {
                    EmptyLauncher(unit: m.unit)
                } else {
                    let focused = apps[layout.selected]
                    let shown = apps.first { $0.id == shelfID } ?? focused
                    let scrolled = layout.scrolled

                    if shelf {
                        // New artwork settles in from slightly closer, over the old one fading out.
                        ShelfArt(service: shown, size: geo.size, unit: m.unit,
                                 drifting: settings.shelfMotion && !reduceMotion, paused: model.zoomed)
                            .id(shown.id)
                            .transition(.asymmetric(
                                insertion: reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)),
                                removal: .opacity))
                            // Recedes as the grid scrolls over it: pushed back, blurred, dimmed, and
                            // drifting up a little behind the rows for depth.
                            .scaleEffect(scrolled && !reduceMotion ? 1.06 : 1)
                            .offset(y: reduceMotion ? 0 : max(layout.scrollOffset * 0.12, -70 * m.unit))
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
                                // Slides in from the side focus moved toward, and the old one out
                                // the other way, so the caption follows your thumb.
                                ShelfCaption(service: shown, unit: m.unit)
                                    .id(shown.id)
                                    .transition(reduceMotion ? .opacity : .asymmetric(
                                        insertion: .opacity.combined(with: .offset(x: nav.width * 40 * m.unit, y: 14 * m.unit)),
                                        removal: .opacity.combined(with: .offset(x: -nav.width * 28 * m.unit))))
                            }
                        }
                        .frame(height: m.headerHeight, alignment: .bottomLeading)
                        .padding(.bottom, m.captionGap)
                        .blur(radius: scrolled && !reduceMotion ? 12 * m.unit : 0)
                        .scaleEffect(scrolled && !reduceMotion ? 0.96 : 1, anchor: .bottomLeading)
                        .opacity(scrolled ? 0 : 1)

                        VStack(alignment: .leading, spacing: m.rowSpacing) {
                            ForEach(0..<m.rows(apps.count), id: \.self) { r in
                                HStack(spacing: m.gap) {
                                    ForEach(r * m.columns..<min((r + 1) * m.columns, apps.count), id: \.self) { i in
                                        AppIcon(service: apps[i], focused: i == layout.selected && !barFocused,
                                                move: nav, trigger: model.navTick, metrics: m,
                                                playing: audio.contains(apps[i].id),
                                                motion: motion, labels: settings.iconLabels)
                                            .zIndex(i == layout.selected ? 1 : 0)
                                            .onTapGesture { model.click(app: i) }
                                            .onHover { if $0 { model.hover(app: i) } }
                                    }
                                }
                                .zIndex(r == layout.row ? 1 : 0)
                                // Rows that have scrolled up past focus fall back, so the one in
                                // focus reads as in front.
                                .opacity(scrolled && r < layout.row ? 0.45 : 1)
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

                // Only reachable from the first row, so it makes way for the row above when the grid
                // scrolls up underneath it.
                let barHidden = !apps.isEmpty && layout.scrolled
                TopBar(unit: m.unit, focused: barFocused, showsClock: settings.showClock)
                    .padding(.trailing, m.sidePadding)
                    .padding(.top, 32 * m.unit)
                    .opacity(barHidden ? 0 : 1)
                    .offset(y: barHidden ? -24 * m.unit : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .task(id: apps.isEmpty ? "" : apps[layout.selected].id) {
                guard !apps.isEmpty else { return }
                let id = apps[layout.selected].id
                // The first time there's nothing to fade from.
                guard shelfID != nil else { return shelfID = id }
                try? await Task.sleep(for: Self.shelfSettle)
                guard !Task.isCancelled, shelfID != id else { return }
                withAnimation(Motion.crossfade) { shelfID = id }
            }
            .animation(motion.scroll, value: layout.row)
            .animation(motion.focus, value: barFocused)
            // Changes made in Settings reshape the Home Screen in place rather than snapping.
            .animation(Motion.expand, value: model.columns)
            .animation(Motion.expand, value: shelf)
            .animation(Motion.expand, value: settings.focusSize)
            .animation(Motion.expand, value: settings.iconLabels)
            .animation(Motion.expand, value: settings.showClock)
        }
        // The laid-out size, not the on-screen one: the launcher is scaled while an app zooms out
        // of it or a screen recedes it, and icon frames are worked out from the unscaled layout.
        .onGeometryChange(for: CGRect.self) { CGRect(origin: $0.frame(in: .global).origin, size: $0.size) } action: {
            model.launcherFrame = $0
        }
    }
}

/// The clock and Settings, above the apps. Up from the first row reaches Settings.
private struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let unit: CGFloat
    let focused: Bool
    var showsClock = true

    var body: some View {
        HStack(spacing: 28 * unit) {
            if showsClock {
                TimelineView(.everyMinute) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30 * unit, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.5), radius: 6 * unit)
                        .animation(Motion.value, value: ctx.date)
                }
                .transition(.opacity.combined(with: .offset(x: 12 * unit)))
            }
            Image(systemName: "gearshape.fill")
                .font(.system(size: 26 * unit, weight: .semibold))
                .foregroundStyle(focused ? .black : .white)
                .frame(width: 64 * unit, height: 64 * unit)
                .glassSurface(Circle(), tint: focused ? .white.opacity(0.92) : nil, interactive: true)
                .scaleEffect(focused ? 1.18 : 1)
                .pressEffect(trigger: model.presses, active: focused)
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
                .font(.system(size: 40 * unit, weight: .bold))
            Text("Open Settings to show or add apps.")
                .font(.system(size: 24 * unit))
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
