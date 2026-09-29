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

/// Layout scaled from tvOS's 1920×1080 home screen.
struct Metrics {
    let size: CGSize
    let columns: Int
    var shelf = true

    var unit: CGFloat { max(size.width / 1920, 0.5) }
    var sidePadding: CGFloat { 90 * unit }
    var gap: CGFloat { 48 * unit }
    var tileWidth: CGFloat { (size.width - 2 * sidePadding - CGFloat(columns - 1) * gap) / CGFloat(columns) }
    var tileHeight: CGFloat { tileWidth * 0.6 }
    var rowSpacing: CGFloat { 84 * unit }
    /// The top shelf, or just room for the hint line when the shelf is off.
    var headerHeight: CGFloat { shelf ? size.height * 0.52 : 90 * unit }
    var captionGap: CGFloat { 44 * unit }
    /// Where a focused lower row settles once the shelf has scrolled away; the row above peeks in.
    var scrolledRowTop: CGFloat { size.height * 0.34 }
    func rowTop(_ row: Int) -> CGFloat { headerHeight + captionGap + CGFloat(row) * (tileHeight + rowSpacing) }
    var corner: CGFloat { tileWidth * 0.055 }

    func rows(_ count: Int) -> Int { (count + columns - 1) / columns }
}

/// The big artwork behind the top shelf. Real tvOS apps supply images; here each service
/// gets a generated composition from its colors and symbol.
struct ShelfArt: View {
    let service: Service
    let size: CGSize
    let unit: CGFloat

    var body: some View {
        let accent = service.accent ?? service.color
        ZStack {
            Color.black
            LinearGradient(colors: [service.color, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(accent)
                .frame(width: size.width * 0.7)
                .blur(radius: 180 * unit)
                .offset(x: size.width * 0.32, y: -size.height * 0.35)
                .opacity(0.8)
            Circle()
                .fill(service.color)
                .frame(width: size.width * 0.5)
                .blur(radius: 160 * unit)
                .offset(x: -size.width * 0.4, y: -size.height * 0.1)
                .opacity(0.6)
            Image(systemName: service.symbol)
                .font(.system(size: size.height * 0.5, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                )
                .rotationEffect(.degrees(-10))
                .offset(x: size.width * 0.26, y: -size.height * 0.2)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.35), location: 0.3),
                .init(color: .black.opacity(0.92), location: 0.55),
                .init(color: .black, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .drawingGroup()
    }
}

struct ShelfCaption: View {
    let service: Service
    let unit: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * unit) {
            Text(service.name)
                .font(.system(size: 92 * unit, weight: .heavy, design: .rounded))
                .shadow(color: .black.opacity(0.4), radius: 20 * unit)
            if !service.tagline.isEmpty {
                Text(service.tagline)
                    .font(.system(size: 28 * unit, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(service.url.host() ?? "")
                .font(.system(size: 18 * unit, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 14 * unit)
                .padding(.vertical, 6 * unit)
                .background(.white.opacity(0.12), in: Capsule())
                .padding(.top, 6 * unit)
        }
        .foregroundStyle(.white)
    }
}

/// An app icon that lifts, glints and tilts toward the direction focus arrived from.
struct AppIcon: View {
    let service: Service
    let focused: Bool
    let move: CGSize
    let trigger: Int
    let metrics: Metrics

    var body: some View {
        let m = metrics
        let shape = RoundedRectangle(cornerRadius: m.corner, style: .continuous)

        VStack(spacing: 0) {
            IconFace(service: service, height: m.tileHeight, unit: m.unit)
            // Specular glare, brightest along the edge focus came from.
            .overlay(LinearGradient(colors: [.white.opacity(focused ? 0.32 : 0.1), .clear],
                                    startPoint: glareStart, endPoint: .center))
            .frame(width: m.tileWidth, height: m.tileHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.25 : 0.08), lineWidth: 1))
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, t in
                let k = focused ? t : 0
                content
                    .rotation3DEffect(.degrees(k * move.width * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(-k * move.height * 9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .offset(x: k * move.width * 6 * m.unit, y: k * move.height * 6 * m.unit)
            } keyframes: { _ in
                CubicKeyframe(1, duration: 0.1)
                SpringKeyframe(0, duration: 0.55, spring: .bouncy)
            }
            .scaleEffect(focused ? 1.15 : 1)
            .shadow(color: .black.opacity(focused ? 0.6 : 0.3),
                    radius: (focused ? 34 : 8) * m.unit, y: (focused ? 28 : 4) * m.unit)

            Text(service.name)
                .font(.system(size: 24 * m.unit, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6 * m.unit)
                .padding(.top, m.tileHeight * 0.075 + 16 * m.unit)
                .opacity(focused ? 1 : 0)
                .frame(height: 0, alignment: .top)
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
    }

    private var glareStart: UnitPoint {
        UnitPoint(x: 0.5 - move.width * 0.5, y: move.height == 0 ? 0 : 0.5 - move.height * 0.5)
    }
}

/// The artwork inside an app icon, shared by the launcher and the settings preview.
struct IconFace: View {
    let service: Service
    let height: CGFloat
    var unit: CGFloat = 1

    var body: some View {
        ZStack {
            LinearGradient(colors: service.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: height * 0.08) {
                Image(systemName: service.symbol)
                    .font(.system(size: height * 0.26, weight: .semibold))
                Text(service.name)
                    .font(.system(size: height * 0.15, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 6 * unit, y: 2 * unit)
            .padding(.horizontal, height * 0.12)
        }
    }
}
