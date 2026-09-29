import SiriRemote

/// Where focus is on the home screen: an app in the grid, or the top bar above it. Pure, so the
/// rules can be tested without a screen.
///
/// - Moves stay where they say: left and right never wrap onto another row, and down from a row
///   that has no row below stays put instead of jumping sideways to the last app.
/// - Vertical moves keep the column you were in, even through a shorter last row.
/// - Up from the first row reaches the top bar, and down from it comes back to the same column.
struct GridFocus: Equatable {
    var index = 0
    var onBar = false
    /// The column vertical moves aim for.
    private(set) var column = 0

    /// Moves focus one step. Returns false at an edge, where nothing changed.
    mutating func move(_ command: RemoteCommand, count: Int, columns: Int) -> Bool {
        guard columns > 0 else { return false }
        guard count > 0 else {
            onBar = true
            return false
        }
        clamp(count: count, columns: columns)
        let row = index / columns
        switch command {
        case .left:
            guard !onBar, index % columns > 0 else { return false }
            index -= 1
            column = index % columns
        case .right:
            guard !onBar, index % columns < columns - 1, index + 1 < count else { return false }
            index += 1
            column = index % columns
        case .up:
            guard !onBar else { return false }
            if row == 0 {
                onBar = true
            } else {
                index = (row - 1) * columns + min(column, columns - 1)
            }
        case .down:
            if onBar {
                onBar = false
                index = min(column, count - 1)
            } else if (row + 1) * columns < count {
                index = min((row + 1) * columns + column, count - 1)
            } else {
                return false
            }
        default:
            return false
        }
        return true
    }

    /// Focuses an app directly, from a click or after opening one.
    mutating func select(_ i: Int, columns: Int) {
        index = max(i, 0)
        onBar = false
        column = columns > 0 ? index % columns : 0
    }

    mutating func selectBar() { onBar = true }

    /// Keeps focus on an app that still exists after apps are hidden or the row length changes.
    mutating func clamp(count: Int, columns: Int) {
        index = min(max(index, 0), max(count - 1, 0))
        column = min(column, max(columns - 1, 0))
    }

    /// Back to the first app, as the TV button does on the home screen.
    mutating func reset(columns: Int) { select(0, columns: columns) }
}
