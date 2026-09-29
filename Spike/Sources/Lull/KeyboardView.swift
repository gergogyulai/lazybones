import SwiftUI

/// The keyboard sheet: what's been typed at the top, suggestions, then the keys. Rises over the
/// bottom of the page so the field and its surroundings stay in view.
struct KeyboardView: View {
    @EnvironmentObject var kb: KeyboardController
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let u = max(geo.size.width / 1920, 0.5)
            let key = 92 * u
            let rows = kb.rows
            let gridWidth = (rows.map(KeyboardController.width).max() ?? 10) * key

            ZStack(alignment: .bottom) {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.7), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

                if let field = kb.field {
                    VStack(spacing: 26 * u) {
                        FieldDisplay(field: field, value: kb.value, host: kb.host, revealed: kb.revealed, accent: accent, u: u)
                            .frame(width: gridWidth)
                        VStack(spacing: KeyboardController.gap * key) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                                HStack(spacing: KeyboardController.gap * key) {
                                    ForEach(row) { k in
                                        KeyCap(key: k, focused: kb.focus == k.id, pressed: kb.flash == k.id,
                                               shift: kb.shift, accent: accent, unit: key, u: u)
                                            .zIndex(kb.focus == k.id ? 1 : 0)
                                            .onTapGesture { kb.hover(k); kb.press(k) }
                                            .onHover { if $0 { kb.hover(k) } }
                                    }
                                }
                                .padding(.bottom, r == 0 ? 10 * u : 0)
                                .zIndex(row.contains { $0.id == kb.focus } ? 1 : 0)
                            }
                        }
                        .animation(.snappy(duration: 0.25), value: kb.mode)
                        hints(u)
                    }
                    .padding(.horizontal, 44 * u)
                    .padding(.top, 36 * u)
                    .padding(.bottom, 26 * u)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 48 * u, style: .continuous)
                        shape.fill(.ultraThinMaterial)
                            .overlay(shape.fill(.black.opacity(0.4)))
                            .overlay(shape.fill(LinearGradient(colors: [accent.opacity(0.14), .clear],
                                                               startPoint: .top, endPoint: .center)))
                            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
                            .shadow(color: .black.opacity(0.55), radius: 50 * u, y: 20 * u)
                    }
                    .padding(.bottom, 40 * u)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func hints(_ u: CGFloat) -> some View {
        HStack(spacing: 22 * u) {
            hint("hand.draw", "Swipe to move")
            hint("circle.circle", "Click to type")
            if kb.mode != .numpad { hint("playpause.fill", "Shift") }
            hint("chevron.left", "Back to close")
        }
        .font(.system(size: 15 * u, weight: .medium))
        .foregroundStyle(.white.opacity(0.38))
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
    }
}

/// The field's label, where it lives, and its text with a caret.
private struct FieldDisplay: View {
    let field: FieldContext
    let value: String
    let host: String
    let revealed: Bool
    let accent: Color
    let u: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * u) {
            HStack(spacing: 12 * u) {
                Image(systemName: symbol)
                    .font(.system(size: 15 * u, weight: .bold))
                    .foregroundStyle(accent)
                    .brightness(0.25)
                Text(field.title.uppercased())
                    .font(.system(size: 15 * u, weight: .semibold))
                    .tracking(1.6 * u)
                    .lineLimit(1)
                    .opacity(0.6)
                Spacer(minLength: 0)
                if field.maxLength > 0 {
                    Text("\(value.count)/\(field.maxLength)")
                        .font(.system(size: 15 * u, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(value.count >= field.maxLength ? AnyShapeStyle(accent) : AnyShapeStyle(.white.opacity(0.45)))
                }
                if !host.isEmpty {
                    Text(host)
                        .font(.system(size: 14 * u, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 12 * u)
                        .padding(.vertical, 5 * u)
                        .background(.white.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 8 * u)

            HStack(spacing: 4 * u) {
                if value.isEmpty {
                    Caret(color: accent, height: 46 * u)
                    Text(field.placeholder.isEmpty ? " " : field.placeholder)
                        .opacity(0.28)
                } else {
                    Text(shown)
                        .tracking(field.kind == .password && !revealed ? 6 * u : 0)
                        .contentTransition(.numericText())
                        .truncationMode(.head)
                    Caret(color: accent, height: 46 * u)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: field.kind.numeric ? 46 * u : 40 * u, weight: .medium,
                          design: field.kind.numeric ? .rounded : .default))
            .monospacedDigit()
            .lineLimit(1)
            .animation(.snappy(duration: 0.18), value: value)
            .padding(.horizontal, 26 * u)
            .frame(height: 84 * u)
            .background {
                let shape = RoundedRectangle(cornerRadius: 24 * u, style: .continuous)
                shape.fill(.black.opacity(0.35))
                    .overlay(shape.strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.25)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2 * u))
            }
        }
    }

    private var shown: String {
        if field.kind == .password && !revealed { return String(repeating: "•", count: value.count) }
        return value.replacingOccurrences(of: "\n", with: " ↵ ")
    }

    private var symbol: String {
        switch field.kind {
        case .search: "magnifyingglass"
        case .email: "at"
        case .url: "globe"
        case .password: "key.fill"
        case .phone: "phone.fill"
        case .code: "number"
        case .number: "textformat.123"
        case .text, .multiline: "character.cursor.ibeam"
        }
    }
}

private struct Caret: View {
    let color: Color
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(color)
            .brightness(0.2)
            .frame(width: max(3, height * 0.065), height: height)
            .phaseAnimator([1.0, 1.0, 0.0]) { caret, opacity in
                caret.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.45) }
    }
}

/// One key. Focus works like tvOS: the key turns white, lifts and casts a shadow.
private struct KeyCap: View {
    let key: KeyboardController.Key
    let focused: Bool
    let pressed: Bool
    let shift: KeyboardController.Shift
    let accent: Color
    /// Points per key width.
    let unit: CGFloat
    let u: CGFloat

    var body: some View {
        let pill = key.kind == .chip || key.kind == .tool
        let height = pill ? 58 * u : 80 * u
        let shape = RoundedRectangle(cornerRadius: pill ? height / 2 : 18 * u, style: .continuous)

        label
            .foregroundStyle(focused ? Color.black : key.kind == .tool ? .white.opacity(0.75) : .white)
            .frame(width: key.width * unit, height: height)
            .background {
                shape.fill(fill)
                    .overlay(shape.strokeBorder(.white.opacity(focused ? 0 : 0.06), lineWidth: 1))
            }
            .overlay(alignment: .top) {
                // A soft top highlight on the focused key, like the glint on tvOS icons.
                if focused {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.9), .clear], startPoint: .top, endPoint: .center))
                        .blendMode(.plusLighter)
                        .opacity(0.35)
                        .allowsHitTesting(false)
                }
            }
            // Wide keys lift by about the same number of points as letters, not the same ratio.
            .scaleEffect(pressed ? 1.0 : focused ? 1 + (pill ? 0.1 : 0.16) / max(1, key.width * 0.8) : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 18 * u, y: 12 * u)
            .animation(.spring(duration: 0.24, bounce: 0.3), value: focused)
            .animation(.spring(duration: 0.14, bounce: 0.5), value: pressed)
            .contentShape(shape)
    }

    private var fill: AnyShapeStyle {
        if focused { return AnyShapeStyle(.white) }
        switch key.kind {
        case .char: return AnyShapeStyle(.white.opacity(0.13))
        case .function: return AnyShapeStyle(.white.opacity(key.action == .shift && shift != .off ? 0.26 : 0.07))
        case .action: return AnyShapeStyle(accent.gradient)
        case .chip: return AnyShapeStyle(.white.opacity(0.16))
        case .tool: return AnyShapeStyle(.white.opacity(0.07))
        }
    }

    @ViewBuilder private var label: some View {
        switch key.kind {
        case .char:
            Text(key.label)
                .font(.system(size: (key.width > 1 ? 40 : 34) * u, weight: key.width > 1 ? .regular : .medium,
                              design: key.width > 1 ? .rounded : .default))
                .contentTransition(.interpolate)
        case .function where key.symbol != nil:
            Image(systemName: key.symbol!)
                .font(.system(size: 26 * u, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        case .function:
            Text(key.label).font(.system(size: 22 * u, weight: .semibold))
        case .action:
            HStack(spacing: 10 * u) {
                Image(systemName: key.symbol ?? "return")
                Text(key.label).lineLimit(1)
            }
            .font(.system(size: 24 * u, weight: .semibold))
        case .chip, .tool:
            HStack(spacing: 8 * u) {
                if let s = key.symbol { Image(systemName: s).opacity(0.7) }
                Text(key.label).lineLimit(1)
            }
            .font(.system(size: 20 * u, weight: key.kind == .chip ? .semibold : .medium))
            .padding(.horizontal, 12 * u)
        }
    }
}
