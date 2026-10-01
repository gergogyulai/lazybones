import SwiftUI

/// tvOS-style volume pill: speaker glyph and a level bar on glass, sized for the room like the
/// rest of the interface (`u` is points per point of a 1920-wide screen).
struct VolumeHUDView: View {
    let state: VolumeState
    var u: CGFloat = 1

    var body: some View {
        let level = state.muted ? 0 : Double(state.level) / 100
        HStack(spacing: 18 * u) {
            Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: level)
                .font(.system(size: 26 * u, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38 * u)
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: geo.size.width * level)
                    }
            }
            .frame(width: 240 * u, height: 10 * u)
            .animation(Motion.value, value: level)
            Text(state.target)
                .font(.system(size: 17 * u, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: 220 * u, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26 * u)
        .padding(.vertical, 20 * u)
        .glassSurface(Capsule())
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}
