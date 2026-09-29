import SwiftUI

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
