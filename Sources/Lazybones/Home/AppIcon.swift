import SwiftUI

/// An app icon that lifts, glints and leans toward the direction focus arrived from, and while
/// focused, tilts under a thumb resting on the clickpad.
///
/// Everything that moves is animated state rather than worked out from the latest press, so a
/// change of direction mid-lean swings smoothly round instead of snapping to the new axis.
struct AppIcon: View {
    @EnvironmentObject private var parallax: Parallax
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let service: Service
    let focused: Bool
    let move: CGSize
    let trigger: Int
    let metrics: Metrics
    /// The app is playing audio behind the Home Screen.
    var playing = false
    var motion = HomeMotion.lively
    var labels = IconLabels.focused

    /// How far the icon leans, -1...1 each way, x right and y down.
    @State private var lean = CGSize.zero
    /// Which push the lean is settling from, so an older one's settle can't cut a newer push short.
    @State private var leanID = 0
    /// How brightly the edge glare shows, 0...1: it catches the light on a move, then fades away.
    @State private var glint = 0.0
    @State private var glintID = 0
    /// Counts the times the icon has taken focus, each running the sweep of light across it.
    @State private var sweeps = 0

    var body: some View {
        let m = metrics
        let shape = RoundedRectangle(cornerRadius: m.corner, style: .continuous)
        let tilt = focused && !reduceMotion && motion.tilts ? parallax.offset : .zero
        let labelShown = labels == .always || (labels == .focused && focused)

        VStack(spacing: 0) {
            IconFace(service: service, height: m.tileHeight, unit: m.unit)
            .overlay {
                Sheen(direction: move, tilt: tilt, glint: glint, width: m.tileWidth)
                    .animation(motion.glint, value: move)
                    .animation(.interactiveSpring(duration: 0.3, extraBounce: 0.1), value: tilt)
                    .animation(motion.focus, value: focused)
            }
            .overlay {
                Color.clear.keyframeAnimator(initialValue: 1.0, trigger: sweeps) { content, t in
                    content.overlay(Sweep(progress: t, direction: move))
                } keyframes: { _ in
                    LinearKeyframe(0, duration: 0)
                    CubicKeyframe(1, duration: 0.75)
                }
            }
            .frame(width: m.tileWidth, height: m.tileHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.25 : 0.08), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if playing {
                    Image(systemName: "waveform")
                        .font(.system(size: 20 * m.unit, weight: .bold))
                        .symbolEffect(.variableColor.iterative.reversing)
                        .foregroundStyle(.white)
                        .padding(9 * m.unit)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(10 * m.unit)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .rotation3DEffect(.degrees(lean.width * motion.lean), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(-lean.height * motion.lean), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .offset(x: lean.width * motion.lean * 0.66 * m.unit, y: lean.height * motion.lean * 0.66 * m.unit)
            .parallax(tilt, unit: m.unit)
            // A soft glow in the app's own color, as if the lit icon spilled onto what's behind it.
            .background {
                shape.fill(service.accent ?? service.color)
                    .blur(radius: 40 * m.unit)
                    .scaleEffect(0.86)
                    .offset(y: 22 * m.unit)
                    .opacity(focused ? 0.4 : 0)
            }
            .scaleEffect(focused ? m.focusScale : 1)
            // The shadow swings away from the light as the icon leans and tilts.
            .shadow(color: .black.opacity(focused ? 0.6 : 0.3),
                    radius: (focused ? 34 : 8) * m.unit,
                    x: (lean.width * 10 + tilt.width * 12) * m.unit,
                    y: ((focused ? 28 : 4) + lean.height * 8 + tilt.height * 10) * m.unit)
            .animation(.interactiveSpring(duration: 0.3, extraBounce: 0.1), value: tilt)

            // Clears the grown icon when focused, and drops in under it as it grows.
            Text(service.name)
                .font(.system(size: 24 * m.unit, weight: .medium))
                .foregroundStyle(.white.opacity(focused ? 1 : 0.6))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.5), radius: 6 * m.unit)
                .padding(.top, (focused ? m.tileHeight * (m.focusScale - 1) / 2 : 0) + 16 * m.unit)
                .offset(y: labelShown ? 0 : -10 * m.unit)
                .opacity(labelShown ? 1 : 0)
                .frame(width: m.tileWidth, height: 0, alignment: .top)
        }
        .animation(motion.focus, value: focused)
        .animation(Motion.focus, value: playing)
        .onChange(of: trigger) { push() }
        .onChange(of: focused) { _, now in
            guard !now else { return }
            // Letting go of focus eases the icon level rather than dropping it flat.
            leanID += 1
            glintID += 1
            withAnimation(motion.focus) {
                lean = .zero
                glint = 0
            }
        }
        // The sweep waits for focus to rest, so skimming across a row doesn't flash every icon.
        .task(id: focused) {
            guard focused, motion.sweeps, !reduceMotion, move != .zero else { return }
            try? await Task.sleep(for: Self.sweepDelay)
            if !Task.isCancelled { sweeps += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(service.name)
        .accessibilityValue(playing ? "Playing" : "")
        .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
    }

    /// Catches the edge glare for a move, and lets it fade once the moves stop.
    private func flash() {
        glintID += 1
        let id = glintID
        withAnimation(.easeOut(duration: 0.15)) {
            glint = 1
        } completion: {
            guard glintID == id else { return }
            withAnimation(.easeOut(duration: 0.15)) { glint = 0 }
        }
    }

    /// How long focus rests on an icon before light sweeps across it.
    private static let sweepDelay = Duration.milliseconds(160)

    /// Leans into the latest move, then settles back. Both are springs, so a new push carries on
    /// from the lean's current angle and speed.
    private func push() {
        guard focused else { return }
        flash()
        guard !reduceMotion, motion.lean > 0 else { return }
        leanID += 1
        let id = leanID
        let target = move
        withAnimation(motion.push) {
            lean = target
        } completion: {
            guard leanID == id else { return }
            withAnimation(motion.settle) { lean = .zero }
        }
    }
}

/// The light on an icon's face: a faint glare along the edge focus is heading for while it moves,
/// and under a thumb resting on the clickpad, a highlight sliding opposite to it, like light on a
/// tilted card. At rest, with neither, the face is clear. Animatable all through,
/// so the light swings round to a new edge instead of jumping there.
private struct Sheen: View, Animatable {
    var direction: CGSize
    var tilt: CGSize
    /// How brightly the edge glare shows, 0...1.
    var glint: Double
    let width: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGSize.AnimatableData, CGSize.AnimatableData>, Double> {
        get { AnimatablePair(AnimatablePair(direction.animatableData, tilt.animatableData), glint) }
        set {
            direction.animatableData = newValue.first.first
            tilt.animatableData = newValue.first.second
            glint = newValue.second
        }
    }

    var body: some View {
        // On the edge focus is heading for: the right after a move right, the top after a move up,
        // and the bottom after a move down. With no move, the top.
        let edge = UnitPoint(x: 0.5 + direction.width * 0.5, y: max(0, direction.height))
        // Fades in as the thumb moves off center, rather than switching on.
        // Eased, so a light touch barely registers and the light builds gently from there.
        let reach = min(1, hypot(tilt.width, tilt.height) * 1.2)
        let pressed = reach * reach * (3 - 2 * reach)

        // Where the light catches the face: away from the thumb, as if it pressed that side down.
        let catchlight = UnitPoint(x: 0.5 - tilt.width * 0.7, y: 0.15 - tilt.height * 0.6)

        ZStack {
            // Under a thumb, the edge glare gives way to the light the touch catches. It's fainter
            // still across a side edge, where it runs the short way over the face, and it falls
            // off gradually over the whole face rather than stopping at the middle.
            let glare = 0.1 * glint * (1 - 0.4 * pressed) * (1 - 0.45 * abs(direction.width))
            LinearGradient(stops: [
                .init(color: .white.opacity(glare), location: 0),
                .init(color: .white.opacity(glare * 0.3), location: 0.35),
                .init(color: .clear, location: 0.8),
            ], startPoint: edge, endPoint: UnitPoint(x: 1 - edge.x, y: 1 - edge.y))
            // A broad wash across the raised side, then a hot spot within it.
            LinearGradient(colors: [.white.opacity(0.05 * pressed), .clear],
                           startPoint: catchlight, endPoint: UnitPoint(x: 1 - catchlight.x, y: 1 - catchlight.y))
                .blendMode(.plusLighter)
            RadialGradient(colors: [.white.opacity(0.17 * pressed), .white.opacity(0.05 * pressed), .clear],
                           center: catchlight, startRadius: 0, endRadius: width * 0.9)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

/// A slanted band of light that crosses an icon once as it takes focus, traveling the way focus
/// moved. `progress` runs 0...1; at 1 (and 0) there's nothing to see.
private struct Sweep: View {
    let progress: Double
    let direction: CGSize

    var body: some View {
        let d = direction == .zero ? CGSize(width: 1, height: 0) : direction
        // Along the move, skewed a little so the band runs at a slant.
        let start = UnitPoint(x: 0.5 - d.width * 0.5 - d.height * 0.3, y: 0.5 - d.height * 0.5 - d.width * 0.3)
        let end = UnitPoint(x: 1 - start.x, y: 1 - start.y)
        let at = -0.2 + progress * 1.4
        let strength = sin(progress * .pi)
        let stop = { (x: Double) in max(0, min(1, x)) }

        if strength > 0.01 {
            LinearGradient(stops: [
                .init(color: .clear, location: stop(at - 0.24)),
                .init(color: .white.opacity(0.09 * strength), location: stop(at)),
                .init(color: .clear, location: stop(at + 0.24)),
            ], startPoint: start, endPoint: end)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }
}

/// The artwork inside an app icon, shared by the launcher and the settings preview.
struct IconFace: View {
    let service: Service
    let height: CGFloat
    var unit: CGFloat = 1
    /// Just the symbol (or the brand's mark), for sizes where the name would be too small to read.
    var compact = false

    var body: some View {
        ZStack {
            LinearGradient(colors: service.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let brand = service.brand, let image = compact ? brand.markImage : brand.logoImage {
                // Sized by height, since icons are 5:3 wherever they're drawn. The logo is the
                // service's own, so it gets no shadow or tint of ours.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: height / 0.6 * (compact ? 0.62 : brand.logoWidth),
                           maxHeight: height * (compact ? 0.62 : 0.5))
            } else if compact {
                Image(systemName: service.symbol)
                    .font(.system(size: height * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            } else {
                name
            }
        }
    }

    private var name: some View {
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
