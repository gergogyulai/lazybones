import SwiftUI

/// Where the thumb rests on the clickpad, for tilting the focused icon under it the way tvOS does.
/// Its own object, rather than part of `AppModel`, because it changes many times a second: only
/// the icons observe it, so the rest of the launcher doesn't redraw with every touch frame.
@MainActor
final class Parallax: ObservableObject {
    /// -1...1 on each axis, x right and y down (screen coordinates). Zero with no thumb resting.
    @Published private(set) var offset = CGSize.zero

    /// `rest` is the remote's reading (y up), or nil once the thumb lifts.
    func update(_ rest: SIMD2<Float>?) {
        let new = rest.map { CGSize(width: CGFloat($0.x), height: -CGFloat($0.y)) } ?? .zero
        if new != offset { offset = new }
    }

    func reset() { update(nil) }
}

extension View {
    /// Tilts and shifts a focused item toward `tilt` (-1...1 each way), as if pressed under a thumb.
    func parallax(_ tilt: CGSize, unit: CGFloat) -> some View {
        rotation3DEffect(.degrees(tilt.width * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(-tilt.height * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .offset(x: tilt.width * 10 * unit, y: tilt.height * 10 * unit)
    }
}
