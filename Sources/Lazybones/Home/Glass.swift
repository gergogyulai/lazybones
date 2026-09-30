import SwiftUI

/// Liquid Glass, the material of the current Apple design system, with a dark material standing in on
/// macOS versions before it. Every floating surface (panels, tiles, pills, buttons) goes through here
/// so the whole app changes together.
extension View {
    /// A glass surface in `shape`. `tint` colors the glass (a strong white tint is how a focused
    /// tile reads as lit) and `interactive` makes it react to being pressed and hovered.
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(.black.opacity(0.3))
                    if let tint { shape.fill(tint.opacity(0.5)) }
                    shape.stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
        }
    }

    @available(macOS 26, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Glass shapes that sit close together, which lets them blend into one another the way Liquid
/// Glass does. Just the content itself before macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
