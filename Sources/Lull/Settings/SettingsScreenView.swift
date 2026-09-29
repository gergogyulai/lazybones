import LGTV
import SwiftUI

/// The settings screen for the remote: pages down the left, the page's rows on the right. Focused
/// items turn white, as in Control Center.
struct SettingsScreenView: View {
    @EnvironmentObject var screen: SettingsScreen
    // Observed so the rows, which read these, redraw when they change.
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tv: TVLink
    @EnvironmentObject var diagnostics: Diagnostics

    var body: some View {
        GeometryReader { geo in
            let u = max(geo.size.width / 1920, 0.55)
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { screen.close() }

                HStack(alignment: .top, spacing: 70 * u) {
                    sidebar(u)
                    content(u)
                }
                .padding(.horizontal, 120 * u)
                .padding(.vertical, 70 * u)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pages

    private func sidebar(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10 * u) {
            Text("Settings")
                .font(.system(size: 64 * u, weight: .heavy, design: .rounded))
                .padding(.bottom, 26 * u)
            GlassGroup(spacing: 10 * u) { VStack(alignment: .leading, spacing: 10 * u) {
            ForEach(SettingsScreen.Page.allCases) { page in
                let selected = screen.page == page
                let focused = selected && screen.inSidebar
                HStack(spacing: 18 * u) {
                    Image(systemName: page.symbol).frame(width: 40 * u)
                    Text(page.title)
                    Spacer()
                }
                .font(.system(size: 28 * u, weight: .semibold))
                .foregroundStyle(focused ? .black : .white)
                .padding(.horizontal, 24 * u)
                .padding(.vertical, 18 * u)
                .modifier(PageGlass(shown: selected, focused: focused, u: u))
                .scaleEffect(focused ? 1.04 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(duration: 0.25, bounce: 0.2)) { screen.select(page: page) }
                }
                .animation(.spring(duration: 0.25, bounce: 0.2), value: focused)
            }
            } }
            Spacer()
            Text("Back to close")
                .font(.system(size: 18 * u))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 440 * u)
    }

    private func content(_ u: CGFloat) -> some View {
        let rows = screen.rows
        return VStack(alignment: .leading, spacing: 22 * u) {
            Text(screen.page.title)
                .font(.system(size: 44 * u, weight: .bold, design: .rounded))
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    GlassGroup(spacing: 12 * u) {
                        VStack(alignment: .leading, spacing: 12 * u) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                rowView(row, focused: !screen.inSidebar && screen.row == i, u: u)
                                    .id(row.id)
                                    .onTapGesture { screen.click(row: i) }
                            }
                        }
                    }
                    .padding(.vertical, 20 * u)
                }
                .scrollClipDisabled()
                .onChange(of: screen.row) { _, i in
                    guard rows.indices.contains(i) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(rows[i].id, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: 900 * u, maxHeight: .infinity, alignment: .topLeading)
        .id(screen.page)
        .transition(.opacity)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: SettingsRow, focused: Bool, u: CGFloat) -> some View {
        switch row.style {
        case .header:
            Text(row.title)
                .font(.system(size: 20 * u, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 18 * u)
                .padding(.horizontal, 8 * u)
        case .note:
            Text(row.title)
                .font(.system(size: 18 * u))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 8 * u)
        default:
            HStack(spacing: 20 * u) {
                if case let .app(s, shown) = row.style {
                    IconFace(service: s, height: 44 * u, unit: 0.3)
                        .frame(width: 73 * u, height: 44 * u)
                        .clipShape(RoundedRectangle(cornerRadius: 9 * u, style: .continuous))
                        .opacity(shown ? 1 : 0.4)
                }
                VStack(alignment: .leading, spacing: 4 * u) {
                    Text(row.title).font(.system(size: 25 * u, weight: .semibold))
                    if let detail = detail(of: row, focused: focused) {
                        Text(detail).font(.system(size: 16 * u, weight: .medium)).opacity(0.6)
                    }
                }
                .lineLimit(2)
                Spacer(minLength: 20 * u)
                trailing(row, focused: focused, u: u)
            }
            .foregroundStyle(focused ? .black : .white)
            .padding(.horizontal, 28 * u)
            .padding(.vertical, 18 * u)
            .frame(minHeight: 76 * u)
            .glassSurface(RoundedRectangle(cornerRadius: 24 * u, style: .continuous),
                          tint: focused ? .white.opacity(0.92) : nil, interactive: row.focusable)
            .scaleEffect(focused ? 1.02 : 1)
            .contentShape(Rectangle())
            .animation(.spring(duration: 0.25, bounce: 0.2), value: focused)
        }
    }

    /// The small line under a row's title. Apps explain how to reorder them while focused.
    private func detail(of row: SettingsRow, focused: Bool) -> String? {
        if case .app = row.style, focused { return "◀ ▶ move along the Home Screen · click to show or hide" }
        return row.detail
    }

    @ViewBuilder
    private func trailing(_ row: SettingsRow, focused: Bool, u: CGFloat) -> some View {
        switch row.style {
        case let .toggle(on):
            // The system switch, so it looks like the rest of macOS (glass knob on macOS 26). Display
            // only: the remote and clicks on the row do the toggling. Scaled up for the distance.
            Toggle("", isOn: .constant(on))
                .labelsHidden()
                .toggleStyle(.switch)
                .allowsHitTesting(false)
                .scaleEffect(1.7 * u)
                .frame(width: 84 * u, height: 48 * u)
                .animation(.spring(duration: 0.3, bounce: 0.2), value: on)
        case let .slider(fraction, label):
            HStack(spacing: 18 * u) {
                if focused { Image(systemName: "chevron.left").opacity(0.5) }
                Capsule()
                    .fill(focused ? .black.opacity(0.15) : .white.opacity(0.2))
                    .frame(width: 280 * u, height: 12 * u)
                    .overlay(alignment: .leading) {
                        Capsule().fill(focused ? .black : .white)
                            .frame(width: 280 * u * min(max(fraction, 0), 1))
                    }
                    .animation(.spring(duration: 0.25), value: fraction)
                Text(label).monospacedDigit().frame(width: 64 * u, alignment: .trailing)
                if focused { Image(systemName: "chevron.right").opacity(0.5) }
            }
            .font(.system(size: 22 * u, weight: .semibold))
        case let .value(text):
            HStack(spacing: 14 * u) {
                if focused, row.adjust != nil { Image(systemName: "chevron.left").opacity(0.5) }
                Text(text).opacity(0.7)
                if focused, row.adjust != nil { Image(systemName: "chevron.right").opacity(0.5) }
            }
            .font(.system(size: 24 * u, weight: .medium))
        case let .app(_, shown):
            Text(shown ? "Shown" : "Hidden")
                .font(.system(size: 22 * u, weight: .medium))
                .opacity(0.7)
        case .button:
            Image(systemName: "chevron.right")
                .font(.system(size: 20 * u, weight: .bold))
                .opacity(0.5)
        case .header, .note:
            EmptyView()
        }
    }
}

/// A page in the sidebar: glass while it's the one showing, brighter while it has focus.
private struct PageGlass: ViewModifier {
    let shown: Bool
    let focused: Bool
    let u: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22 * u, style: .continuous)
        if shown {
            content.glassSurface(shape, tint: focused ? .white.opacity(0.92) : nil, interactive: true)
        } else {
            content.contentShape(shape)
        }
    }
}
