import Foundation
import BorderlessCore

/// A physical display can pause on older pages independently of phone scrolling.
struct DisplayPageCursor {
    private var page: Int?
    private var follow = HistoryFollow()

    func index(count: Int) -> Int {
        guard count > 0 else { return 0 }
        guard let page, !follow.following else { return count - 1 }
        return min(max(0, page), count - 1)
    }

    mutating func move(_ delta: Int, count: Int, now: TimeInterval) {
        guard count > 0 else { return }
        page = min(max(0, index(count: count) + delta), count - 1)
        follow.scroll(atBottom: page == count - 1, now: now)
    }

    mutating func resume() { page = nil; follow.resume() }
    mutating func tick(now: TimeInterval) -> Bool {
        if follow.tick(now: now) { page = nil; return true }
        return false
    }
}
