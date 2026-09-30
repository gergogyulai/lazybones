import CoreGraphics

/// Layout scaled from tvOS's 1920×1080 home screen.
struct Metrics {
    let size: CGSize
    let columns: Int
    var shelf = true

    var unit: CGFloat { max(size.width / 1920, 0.5) }
    var sidePadding: CGFloat { 90 * unit }
    var gap: CGFloat { 48 * unit }
    var tileWidth: CGFloat { (size.width - 2 * sidePadding - CGFloat(columns - 1) * gap) / CGFloat(columns) }
    var tileHeight: CGFloat { tileWidth * 0.6 }
    var rowSpacing: CGFloat { 84 * unit }
    /// The top shelf, or just room for the hint line when the shelf is off.
    var headerHeight: CGFloat { shelf ? size.height * 0.52 : 90 * unit }
    var captionGap: CGFloat { 44 * unit }
    /// Where a focused lower row settles once the shelf has scrolled away; the row above peeks in.
    var scrolledRowTop: CGFloat { size.height * 0.34 }
    func rowTop(_ row: Int) -> CGFloat { headerHeight + captionGap + CGFloat(row) * (tileHeight + rowSpacing) }
    var corner: CGFloat { tileWidth * 0.055 }

    func rows(_ count: Int) -> Int { (count + columns - 1) / columns }
}

/// Where everything on the home screen sits for a given focus. The launcher draws from it, and the
/// zoom transition uses it to grow out of, and shrink back into, exactly the right icon.
struct LauncherLayout {
    /// How much the focused icon grows.
    static let focusScale: CGFloat = 1.15

    let metrics: Metrics
    let count: Int
    let selected: Int
    /// Whether an app (rather than the top bar) has focus.
    let appFocused: Bool

    init(size: CGSize, columns: Int, shelf: Bool, count: Int, selected: Int, appFocused: Bool = true) {
        metrics = Metrics(size: size, columns: columns, shelf: shelf)
        self.count = count
        self.selected = count > 0 ? min(max(selected, 0), count - 1) : 0
        self.appFocused = appFocused
    }

    var row: Int { selected / metrics.columns }

    /// Whether the shelf has scrolled away (or, with no shelf, the focused row would run off screen).
    var scrolled: Bool {
        metrics.shelf ? row > 0 : metrics.rowTop(row) + metrics.tileHeight + metrics.rowSpacing > metrics.size.height
    }

    /// How far the grid has moved up to keep the focused row in view.
    var scrollOffset: CGFloat { scrolled ? metrics.scrolledRowTop - metrics.rowTop(row) : 0 }

    /// The icon's on-screen frame, with the scroll and, for the focused icon, its growth.
    func frame(of index: Int) -> CGRect {
        let m = metrics
        let r = index / m.columns, c = index % m.columns
        let base = CGRect(x: m.sidePadding + CGFloat(c) * (m.tileWidth + m.gap),
                          y: m.rowTop(r) + scrollOffset, width: m.tileWidth, height: m.tileHeight)
        guard appFocused, index == selected else { return base }
        let s = Self.focusScale
        return base.insetBy(dx: -base.width * (s - 1) / 2, dy: -base.height * (s - 1) / 2)
    }

    /// The corner radius of the icon at `index`, matching `frame(of:)`.
    func corner(of index: Int) -> CGFloat {
        metrics.corner * (appFocused && index == selected ? Self.focusScale : 1)
    }
}
