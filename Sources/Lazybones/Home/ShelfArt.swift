import SwiftUI

/// The big artwork behind the top shelf. Real tvOS apps supply images; here each service
/// gets a generated composition from its colors and its symbol, or its brand's mark.
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
            watermark
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
