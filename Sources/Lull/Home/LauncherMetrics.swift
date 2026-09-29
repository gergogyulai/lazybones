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
