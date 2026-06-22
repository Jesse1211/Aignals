import XCTest
@testable import AignalsCore

/// Unit tests for the pure session-ordering rule (ADR-16 / ADR-19 / INV-11),
/// factored out of the untestable `AppViewModel`.
final class SessionOrderingTests: XCTestCase {

    private func session(_ id: String, startedAt: Date) -> Session {
        Session(
            sessionID: id,
            tool: "claude",
            pid: nil,
            projectName: id,
            cwd: nil,
            startedAt: startedAt,
            updatedAt: startedAt,
            state: .working,
            currentAction: nil
        )
    }

    /// Helper: build a lookup closure from an id→override map.
    private func lookup(_ map: [String: OrderingOverride]) -> (Session) -> OrderingOverride? {
        { map[$0.sessionID] }
    }

    private func ids(_ sessions: [Session]) -> [String] { sessions.map(\.sessionID) }

    /// ADR-16 core regression: after sessions A, B, C are ordered by a drag, a
    /// NEW session D (no override) must land on TOP — not the bottom.
    func testNewSessionSortsToTopAfterOthersOrdered() {
        let base = Date(timeIntervalSince1970: 1000)
        let a = session("A", startedAt: base)
        let b = session("B", startedAt: base + 1)
        let c = session("C", startedAt: base + 2)
        let d = session("D", startedAt: base + 3) // newest, just appeared

        // A,B,C were stamped by a prior drag; D is orderless.
        let map: [String: OrderingOverride] = [
            "A": .init(order: 0, pinned: false),
            "B": .init(order: 1, pinned: false),
            "C": .init(order: 2, pinned: false),
        ]
        let sorted = SessionOrdering.sorted([a, b, c, d], overrideFor: lookup(map))
        XCTAssertEqual(ids(sorted).first, "D", "a brand-new orderless session must sort to the top")
        XCTAssertEqual(ids(sorted), ["D", "A", "B", "C"])
    }

    /// Two orderless new sessions break ties newest-first.
    func testMultipleOrderlessSortNewestFirst() {
        let base = Date(timeIntervalSince1970: 2000)
        let older = session("OLD", startedAt: base)
        let newer = session("NEW", startedAt: base + 10)
        let sorted = SessionOrdering.sorted([older, newer], overrideFor: { _ in nil })
        XCTAssertEqual(ids(sorted), ["NEW", "OLD"])
    }

    /// Explicit order is respected ascending among ordered sessions.
    func testExplicitOrderAscending() {
        let base = Date(timeIntervalSince1970: 3000)
        let x = session("X", startedAt: base)
        let y = session("Y", startedAt: base + 1)
        let map: [String: OrderingOverride] = [
            "X": .init(order: 5, pinned: false),
            "Y": .init(order: 1, pinned: false),
        ]
        let sorted = SessionOrdering.sorted([x, y], overrideFor: lookup(map))
        XCTAssertEqual(ids(sorted), ["Y", "X"])
    }

    /// Pinned sessions sort above unpinned regardless of order/startedAt.
    func testPinnedSortAboveUnpinned() {
        let base = Date(timeIntervalSince1970: 4000)
        let pinnedOld = session("P", startedAt: base)            // older but pinned
        let unpinnedNew = session("U", startedAt: base + 100)    // newer, unpinned
        let map: [String: OrderingOverride] = [
            "P": .init(order: nil, pinned: true),
        ]
        let sorted = SessionOrdering.sorted([unpinnedNew, pinnedOld], overrideFor: lookup(map))
        XCTAssertEqual(ids(sorted).first, "P", "pinned must sort above unpinned")
    }

    /// Pinned-reorder regression: two PINNED rows with explicit order must honor
    /// that order among themselves (previously pinned sorted by startedAt only,
    /// so a pinned reorder never persisted).
    func testPinnedRowsReorderPersistsViaOrder() {
        let base = Date(timeIntervalSince1970: 5000)
        // p1 is OLDER than p2. By startedAt alone p2 (newer) would sort first.
        let p1 = session("P1", startedAt: base)
        let p2 = session("P2", startedAt: base + 50)
        // User dragged P1 above P2 → P1.order=0, P2.order=1.
        let map: [String: OrderingOverride] = [
            "P1": .init(order: 0, pinned: true),
            "P2": .init(order: 1, pinned: true),
        ]
        let sorted = SessionOrdering.sorted([p2, p1], overrideFor: lookup(map))
        XCTAssertEqual(ids(sorted), ["P1", "P2"],
                       "dragging two pinned rows must persist via override.order, not fall back to startedAt")
    }

    /// A pinned orderless row and a pinned ordered row: orderless (new pin)
    /// sorts above within the pinned group too (consistent rule).
    func testPinnedGroupOrderlessAboveOrdered() {
        let base = Date(timeIntervalSince1970: 6000)
        let ordered = session("ORD", startedAt: base + 100)
        let fresh = session("FRESH", startedAt: base)
        let map: [String: OrderingOverride] = [
            "ORD": .init(order: 0, pinned: true),
            "FRESH": .init(order: nil, pinned: true),
        ]
        let sorted = SessionOrdering.sorted([ordered, fresh], overrideFor: lookup(map))
        XCTAssertEqual(ids(sorted).first, "FRESH")
    }
}
