import SwiftUI

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
