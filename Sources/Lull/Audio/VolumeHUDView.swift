import SwiftUI

/// tvOS-style volume pill: speaker glyph and a level bar on a dark material.
struct VolumeHUDView: View {
    let state: VolumeState

    var body: some View {
        let level = state.muted ? 0 : Double(state.level) / 100
        HStack(spacing: 14) {
            Image(systemName: state.muted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: level)
                .font(.system(size: 20, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30)
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: geo.size.width * level)
                    }
            }
            .frame(width: 180, height: 8)
            .animation(.spring(duration: 0.25), value: level)
            Text(state.target)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassSurface(Capsule())
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}
