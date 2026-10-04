import SiriRemote
import SwiftUI

// MARK: - View

/// The 2021+ Siri Remote: aluminium body, black clickpad and buttons, Siri on the right side. Just
/// the device; `RemoteWindowContent` puts it in its window.
struct RemoteView: View {
    @EnvironmentObject var sim: RemoteSimulator

    private let bodySize = CGSize(width: 150, height: 520)
    private let button: CGFloat = 46
    private let gap: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topTrailing) {
            remoteBody
            // Siri, on the right edge.
            SideButton(pressed: sim.isDown(.siri))
                .offset(x: 4, y: 180)
                .pressable(.siri, sim)
            Text(RemoteSimulator.Button.siri.keyLabel)
                .imprint(onDark: false)
                .offset(x: -8, y: 212)
        }
        .frame(width: bodySize.width + 4, height: bodySize.height)
    }

    private var remoteBody: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(RemoteSimulator.Button.power.keyLabel).imprint(onDark: false)
                RoundButton(symbol: "power", key: nil, size: 24, pressed: sim.isDown(.power))
                    .pressable(.power, sim)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Clickpad()
                .padding(.top, 10)

            HStack(alignment: .top, spacing: gap * 2) {
                VStack(spacing: gap) {
                    round(.back, "chevron.left")
                    round(.playPause, "playpause.fill")
                    round(.mute, "speaker.slash.fill")
                }
                VStack(spacing: gap) {
                    round(.home, "tv")
                    VolumeRocker(width: button, height: button * 2 + gap)
                }
            }
            .padding(.top, 26)

            Spacer()
            Text("lazybones")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.18))
                .padding(.bottom, 26)
        }
        .frame(width: bodySize.width, height: bodySize.height)
        .background {
            shape
                .fill(LinearGradient(stops: [
                    .init(color: Color(white: 0.74), location: 0),
                    .init(color: Color(white: 0.9), location: 0.18),
                    .init(color: Color(white: 0.95), location: 0.5),
                    .init(color: Color(white: 0.86), location: 0.85),
                    .init(color: Color(white: 0.7), location: 1),
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.08)],
                                                   startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .overlay(shape.stroke(.black.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                // Drag the aluminium to move the remote; buttons and the clickpad keep their own gestures.
                .gesture(WindowDragGesture())
        }
    }

    private func round(_ b: RemoteSimulator.Button, _ symbol: String) -> some View {
        RoundButton(symbol: symbol, key: b.keyLabel, size: button, pressed: sim.isDown(b))
            .pressable(b, sim)
    }
}

private struct RoundButton: View {
    let symbol: String
    let key: String?
    let size: CGFloat
    let pressed: Bool
    @AppStorage(RemoteSimulator.Preference.showsKeys) private var showsKeys = true

    var body: some View {
        // The symbol moves up to make room for the key under it, and is centred without one.
        let labelled = key != nil && showsKeys
        ZStack {
            Circle()
                .fill(LinearGradient(colors: pressed ? [Color(white: 0.05), Color(white: 0.1)]
                                                     : [Color(white: 0.2), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(pressed ? 0.04 : 0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(pressed ? 0.1 : 0.35), radius: pressed ? 0.5 : 1.5, y: pressed ? 0 : 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: labelled ? -3 : 0)
            if let key {
                Text(key).imprint().offset(y: size * 0.3)
            }
        }
        .animation(.easeOut(duration: 0.15), value: labelled)
        .frame(width: size, height: size)
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct VolumeRocker: View {
    @EnvironmentObject var sim: RemoteSimulator
    @AppStorage(RemoteSimulator.Preference.showsKeys) private var showsKeys = true
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let upPressed = sim.isDown(.volumeUp)
        let downPressed = sim.isDown(.volumeDown)
        VStack(spacing: 0) {
            half("plus", RemoteSimulator.Button.volumeUp, pressed: upPressed)
            half("minus", RemoteSimulator.Button.volumeDown, pressed: downPressed)
        }
        .frame(width: width, height: height)
        .background(
            Capsule().fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        )
        .clipShape(Capsule())
        // Rocks toward the pressed end.
        .rotation3DEffect(.degrees(upPressed ? 6 : downPressed ? -6 : 0), axis: (x: 1, y: 0, z: 0))
        .animation(.easeOut(duration: 0.08), value: upPressed || downPressed)
    }

    private func half(_ symbol: String, _ b: RemoteSimulator.Button, pressed: Bool) -> some View {
        // The key only takes room when it's shown, so without it the symbol is centred.
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
            if showsKeys { Text(b.keyLabel).imprint().transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: showsKeys)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pressed ? Color.black.opacity(0.35) : .clear)
        .contentShape(Rectangle())
        .pressable(b, sim)
    }
}

private struct SideButton: View {
    let pressed: Bool

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .leading, endPoint: .trailing))
            .overlay(Image(systemName: "mic.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.7)))
            .frame(width: 8, height: 50)
            .offset(x: pressed ? -2 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// The touch-sensitive clickpad. Tap the ring for a direction or the centre to select; hold to
/// keep a direction pressed (it auto-repeats); drag to swipe.
private struct Clickpad: View {
    @EnvironmentObject var sim: RemoteSimulator
    @State private var finger: CGPoint?
    @State private var mode = Mode.idle
    @State private var anchor = CGPoint.zero
    @State private var holdTask: Task<Void, Never>?

    private enum Mode { case idle, pending(RemoteSimulator.Button), holding(RemoteSimulator.Button), swiping }

    private let size: CGFloat = 124
    /// Drag distance per swipe step, roughly the hardware's 30% of the surface.
    private var step: CGFloat { size * 0.24 }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.13), Color(white: 0.05)], center: .center,
                                     startRadius: 0, endRadius: size / 2))
                .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1).padding(1))
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            // The inner area that clicks as Select.
            Circle()
                .strokeBorder(.white.opacity(sim.isDown(.select) ? 0.25 : 0.06), lineWidth: 1)
                .background(Circle().fill(.white.opacity(sim.isDown(.select) ? 0.08 : 0)))
                .frame(width: size * 0.5, height: size * 0.5)
            Text(RemoteSimulator.Button.select.keyLabel).imprint()

            ForEach([RemoteSimulator.Button.up, .down, .left, .right], id: \.self) { b in
                ringMark(b)
            }

            if let finger {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 22, height: 22)
                    .blur(radius: 2)
                    .position(finger)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isClicked ? 0.985 : 1)
        .animation(.easeOut(duration: 0.08), value: isClicked)
        .contentShape(Circle())
        .help("Click the centre to select, the ring for a direction (hold to repeat). Drag, scroll with two fingers or press ⇧ arrows to swipe.")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(changed)
                .onEnded { _ in ended() }
        )
    }

    private var isClicked: Bool {
        [RemoteSimulator.Button.up, .down, .left, .right, .select].contains { sim.isDown($0) }
    }

    private func ringMark(_ b: RemoteSimulator.Button) -> some View {
        let r = size / 2 - 13
        let offset: CGSize = switch b {
        case .up: CGSize(width: 0, height: -r)
        case .down: CGSize(width: 0, height: r)
        case .left: CGSize(width: -r, height: 0)
        default: CGSize(width: r, height: 0)
        }
        let on = sim.isDown(b)
        return ZStack {
            Circle().fill(.white.opacity(on ? 0.16 : 0)).frame(width: 30, height: 30).blur(radius: 4)
            Text(b.keyLabel).imprint().opacity(on ? 1 : 0.9)
        }
        .offset(offset)
    }

    private func region(at p: CGPoint) -> RemoteSimulator.Button {
        let dx = p.x - size / 2, dy = p.y - size / 2
        if hypot(dx, dy) < size * 0.25 { return .select }
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }

    private func changed(_ v: DragGesture.Value) {
        finger = v.location
        defer { reportRest(v.location) }
        switch mode {
        case .idle:
            let b = region(at: v.startLocation)
            mode = .pending(b)
            anchor = v.startLocation
            // Held still: a long click, which auto-repeats for directions.
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, case .pending(b) = mode else { return }
                mode = .holding(b)
                // A click takes the finger's rest away, as on the hardware.
                sim.rest(nil)
                sim.down(b)
            }
        case .pending:
            if hypot(v.location.x - anchor.x, v.location.y - anchor.y) > 6 {
                holdTask?.cancel()
                mode = .swiping
                sim.touch(.began, at: surface(anchor))
                sim.touch(.moved, at: surface(v.location))
                swipe(v.location)
            }
        case .holding:
            break
        case .swiping:
            sim.touch(.moved, at: surface(v.location))
            swipe(v.location)
        }
    }

    /// A point on the clickpad as the touch surface reports it: 0...1 across, y up.
    private func surface(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(p.x / size), Float(1 - p.y / size))
    }

    private func swipe(_ p: CGPoint) {
        let dx = p.x - anchor.x, dy = p.y - anchor.y
        if abs(dx) >= step, abs(dx) >= abs(dy) {
            sim.swipe(dx > 0 ? .right : .left)
            anchor.x += dx > 0 ? step : -step
            anchor.y = p.y
        } else if abs(dy) >= step {
            sim.swipe(dy > 0 ? .down : .up)
            anchor.y += dy > 0 ? step : -step
            anchor.x = p.x
        }
    }

    /// Where the finger rests from where focus last moved, in swipe steps, for the icon's tilt.
    private func reportRest(_ p: CGPoint) {
        if case .holding = mode { return }
        sim.rest(SIMD2(Float((p.x - anchor.x) / step), Float((anchor.y - p.y) / step)))
    }

    private func ended() {
        holdTask?.cancel()
        sim.rest(nil)
        switch mode {
        case let .pending(b): sim.tap(b)
        case let .holding(b): sim.up(b)
        case .swiping: sim.touch(.ended, at: surface(finger ?? anchor))
        case .idle: break
        }
        mode = .idle
        withAnimation(.easeOut(duration: 0.15)) { finger = nil }
    }
}

private extension View {
    /// Mouse down/up on a button, so holds (TV) and auto-repeat work like the hardware.
    func pressable(_ b: RemoteSimulator.Button, _ sim: RemoteSimulator) -> some View {
        gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in sim.down(b) }
                .onEnded { _ in sim.up(b) }
        )
    }
}

private extension Text {
    /// The tiny keybind printed on a button, unless key labels are switched off.
    func imprint(onDark: Bool = true) -> some View {
        font(.system(size: 7.5, weight: .semibold, design: .rounded))
            .foregroundStyle(onDark ? Color.white.opacity(0.42) : Color.black.opacity(0.35))
            .modifier(KeyLabelVisibility())
    }
}

private struct KeyLabelVisibility: ViewModifier {
    @AppStorage(RemoteSimulator.Preference.showsKeys) private var shows = true

    func body(content: Content) -> some View {
        content.opacity(shows ? 1 : 0).animation(.easeOut(duration: 0.15), value: shows)
    }
}
