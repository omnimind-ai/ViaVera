import Foundation

nonisolated struct TerminalViewportSize: Equatable, Sendable {
    let columns: Int
    let rows: Int

    init(columns: Int = 80, rows: Int = 24) {
        self.columns = min(max(columns, 20), 240)
        self.rows = min(max(rows, 4), 120)
    }
}
