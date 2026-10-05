import SwiftUI

/// The big artwork behind the top shelf. Real tvOS apps supply images; here each service
/// gets a generated composition from its colors and its symbol, or its brand's mark.
struct ShelfArt: View {
    let service: Service
    let size: CGSize
    let unit: CGFloat
    /// Lets the light in the artwork drift slowly, like a living backdrop. It holds still otherwise.
    var drifting = false
    /// Holds the drift where it is, while nothing can see it.
    var paused = false

    var body: some View {
        // Paced by the clock rather than by state, so artwork swapped in mid-drift picks up exactly
        // where the last one was and the crossfade between them doesn't jump.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !drifting || paused)) { ctx in
            art(drift: drifting ? Drift(ctx.date) : Drift())
        }
        .frame(width: size.width, height: size.height)
    }

    private func art(drift d: Drift) -> some View {
        let accent = service.accent ?? service.color
        return ZStack {
            Color.black
            LinearGradient(colors: [service.color, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(accent)
                .frame(width: size.width * 0.7)
                .scaleEffect(1 + 0.08 * d.b)
                .blur(radius: 180 * unit)
                .offset(x: size.width * (0.32 + 0.05 * d.a), y: -size.height * (0.35 + 0.05 * d.b))
                .opacity(0.8)
            Circle()
                .fill(service.color)
                .frame(width: size.width * 0.5)
                .blur(radius: 160 * unit)
                .offset(x: -size.width * (0.4 - 0.06 * d.b), y: -size.height * (0.1 - 0.06 * d.a))
                .opacity(0.6)
            watermark
                .rotationEffect(.degrees(-10 + 2.5 * d.a))
                .offset(x: size.width * (0.26 - 0.012 * d.b), y: -size.height * (0.2 + 0.015 * d.a))
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

    /// Two slow, out-of-step waves (-1...1) that never quite repeat together.
    private struct Drift {
        var a: CGFloat = 0
        var b: CGFloat = 0

        init() {}

        init(_ date: Date) {
            let t = date.timeIntervalSinceReferenceDate
            a = CGFloat(sin(t * 2 * .pi / 23))
            b = CGFloat(sin(t * 2 * .pi / 31 + 1))
        }
    }

    /// The symbol, or the brand's mark as a silhouette, fading out toward the bottom.
    @ViewBuilder private var watermark: some View {
        let fade = LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
        if let mark = service.brand?.markImage {
            fade
                .frame(width: size.height * 0.55, height: size.height * 0.55)
                .mask(Image(nsImage: mark).resizable().aspectRatio(contentMode: .fit))
        } else {
            Image(systemName: service.symbol)
                .font(.system(size: size.height * 0.5, weight: .bold))
                .foregroundStyle(fade)
        }
    }
}

struct ShelfCaption: View {
    let service: Service
    let unit: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * unit) {
            Group {
                if let brand = service.brand, let logo = brand.logoImage {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 80 * unit * brand.shelfHeight, alignment: .leading)
                        .padding(.bottom, 10 * unit)
                        .accessibilityLabel(service.name)
                } else {
                    Text(service.name)
                        .font(.system(size: 92 * unit, weight: .bold))
                }
            }
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
                .glassSurface(Capsule())
                .padding(.top, 6 * unit)
        }
        .foregroundStyle(.white)
    }
}
