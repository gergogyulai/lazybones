import SwiftUI

/// The cursor over a page: a white dot with a dark rim and a soft shadow, so it reads on dark and
/// light pages alike from across the room. Over a button or link it grows into a lit outline
/// around it, with a small dot left where it points, and it dips under a click.
struct CursorView: View {
    @ObservedObject var cursor: CursorController

    var body: some View {
        // Points are the page's, and the page may not start where this view does (windowed, it
        // starts below the title bar), so line the two up.
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            drawing.offset(x: cursor.appearance.page.minX - origin.x, y: cursor.appearance.page.minY - origin.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var drawing: some View {
        let a = cursor.appearance
        let d = a.diameter
        let dot = CGRect(x: a.point.x - d / 2, y: a.point.y - d / 2, width: d, height: d)
        let m = a.morph
        let shape = Self.mix(dot, a.highlight, m)
        let corner = d / 2 + (min(12 * d / 34, a.highlight.height / 2) - d / 2) * m
        let outline = RoundedRectangle(cornerRadius: max(corner, 0), style: .continuous)

        ZStack(alignment: .topLeading) {
            outline
                .fill(.white.opacity(0.92 - 0.78 * m))
                .overlay(outline.strokeBorder(.white.opacity(0.95 * m), lineWidth: max(3 * d / 34, 2)))
                .overlay(outline.stroke(.black.opacity(0.4), lineWidth: max(1.5 * d / 34, 1)))
                .shadow(color: .black.opacity(0.45), radius: d * 0.3, y: d * 0.08)
                .frame(width: shape.width, height: shape.height)
                .animation(.easeOut(duration: 0.1)) { $0.scaleEffect(a.pressed ? 0.86 : 1) }
                .offset(x: shape.minX, y: shape.minY)
            // Where it points, once the outline has taken over.
            let pip = d * 0.26
            Circle()
                .fill(.white)
                .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                .frame(width: pip, height: pip)
                .opacity(m)
                .offset(x: a.point.x - pip / 2, y: a.point.y - pip / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(a.visible ? 1 : 0)
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}
