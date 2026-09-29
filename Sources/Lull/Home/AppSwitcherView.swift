import SwiftUI

/// A row of cards, one per running app, over a dimmed Home Screen.
struct AppSwitcherView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var switcher: AppSwitcher

    var body: some View {
        GeometryReader { geo in
            let u = max(geo.size.width / 1920, 0.55)
            let cardWidth = 600 * u
            let audio = Set(model.backgroundAudio.map(\.id))

            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { model.perform(AppSwitcher.Action.dismiss) }

                if switcher.apps.isEmpty {
                    VStack(spacing: 14 * u) {
                        Image(systemName: "rectangle.on.rectangle.slash")
                            .font(.system(size: 64 * u, weight: .light))
                        Text("No Apps Open")
                            .font(.system(size: 40 * u, weight: .bold, design: .rounded))
                        Text("Apps you open stay here until you close them.")
                            .font(.system(size: 22 * u))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .transition(.opacity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 56 * u) {
                                ForEach(Array(switcher.apps.enumerated()), id: \.element.id) { i, s in
                                    card(s, focused: i == switcher.focus, playing: audio.contains(s.id),
                                         width: cardWidth, u: u)
                                        .id(s.id)
                                        .onTapGesture {
                                            switcher.focus = i
                                            model.perform(AppSwitcher.Action.resume(s))
                                        }
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, max((geo.size.width - cardWidth) / 2, 60 * u))
                            .padding(.vertical, 60 * u)
                        }
                        .scrollClipDisabled()
                        .onChange(of: switcher.focus) { _, i in
                            guard switcher.apps.indices.contains(i) else { return }
                            withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
                                proxy.scrollTo(switcher.apps[i].id, anchor: .center)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                Text(switcher.apps.isEmpty ? "Back to close" : "Click to open · swipe up to close an app · Back to dismiss")
                    .font(.system(size: 20 * u, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 56 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .foregroundStyle(.white)
    }

    private func card(_ s: Service, focused: Bool, playing: Bool, width: CGFloat, u: CGFloat) -> some View {
        let height = width * 9 / 16
        let shape = RoundedRectangle(cornerRadius: 28 * u, style: .continuous)

        return VStack(spacing: 24 * u) {
            ZStack {
                if let image = switcher.snapshots[s.id] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    IconFace(service: s, height: height, unit: u * 2)
                }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.5 : 0.12), lineWidth: focused ? 3 : 1))
            .overlay(alignment: .topLeading) {
                if focused {
                    Button { model.perform(AppSwitcher.Action.quit(s)) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20 * u, weight: .bold))
                            .frame(width: 48 * u, height: 48 * u)
                            .glassSurface(Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .padding(16 * u)
                    .help("Close \(s.name)")
                    .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(focused ? 0.55 : 0.3), radius: (focused ? 40 : 14) * u, y: (focused ? 26 : 8) * u)

            HStack(spacing: 14 * u) {
                IconFace(service: s, height: 34 * u, unit: 0.3)
                    .frame(width: 57 * u, height: 34 * u)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * u, style: .continuous))
                Text(s.name).font(.system(size: 28 * u, weight: .semibold))
                if playing {
                    Image(systemName: "waveform")
                        .font(.system(size: 22 * u, weight: .bold))
                        .symbolEffect(.variableColor.iterative.reversing)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 18 * u)
            .padding(.vertical, 10 * u)
            .glassSurface(Capsule(), tint: focused ? .white.opacity(0.12) : nil)
        }
        .scaleEffect(focused ? 1.08 : 0.94)
        .opacity(focused ? 1 : 0.6)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: focused)
    }
}
