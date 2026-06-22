import Foundation

/// Pure, testable ordering logic for the session list (ADR-16 / ADR-19 / INV-11).
///
/// `AppViewModel` is not in the SwiftPM test bundle, so the ordering rule lives
/// here as a free function over a minimal protocol the view-model's `Session`
/// satisfies. It returns the sessions in display order.
///
/// Rules (INV-11), top to bottom:
///   1. PINNED sessions sort first. Among pinned, an explicit `override.order`
///      decides (ascending); pinned rows WITHOUT an order fall back to
///      `startedAt` (newest on top). This lets two pinned rows be dragged and
///      have the reorder persist (the previous code sorted pinned by
///      `startedAt` only, so a pinned reorder never stuck).
///   2. Then UNPINNED sessions. A brand-new session has NO `override.order`;
///      it must appear at the TOP of its group even after other sessions have
///      been ordered (ADR-16 "new sessions at the top"). We therefore treat an
///      absent order as ranking ABOVE any explicit order, breaking ties among
///      orderless sessions by `startedAt` (newest first). Among ordered
///      sessions, ascending `order` wins.
///
/// The key correctness point vs. the old `(.none,.some) -> false` rule: an
/// orderless (new) session now sorts ABOVE ordered ones instead of below, so a
/// new session lands on top even after a prior drag stamped the others.
public protocol OrderableSession {
    var orderKey: String { get }
    var startedAtKey: Date { get }
}

/// Look up the persisted preferences a session may carry.
public struct OrderingOverride {
    public let order: Int?
    public let pinned: Bool
    public init(order: Int?, pinned: Bool) {
        self.order = order
        self.pinned = pinned
    }
}

extension Session: OrderableSession {
    public var orderKey: String { sessionID }
    public var startedAtKey: Date { startedAt }
}

public enum SessionOrdering {
    /// Sort `sessions` into display order using `overrideFor` to fetch each
    /// session's persisted order/pinned preferences.
    public static func sorted<S: OrderableSession>(
        _ sessions: [S],
        overrideFor: (S) -> OrderingOverride?
    ) -> [S] {
        sessions.sorted { a, b in
            isOrderedBefore(a, b, overrideFor: overrideFor)
        }
    }

    /// The strict-weak-ordering predicate: is `a` displayed above `b`?
    static func isOrderedBefore<S: OrderableSession>(
        _ a: S,
        _ b: S,
        overrideFor: (S) -> OrderingOverride?
    ) -> Bool {
        let oa = overrideFor(a)
        let ob = overrideFor(b)
        let pa = oa?.pinned ?? false
        let pb = ob?.pinned ?? false

        // 1. pinned group sorts above the unpinned group.
        if pa != pb { return pa }

        // Within the SAME group (both pinned or both unpinned) the same
        // order-vs-startedAt rule applies, so pinned rows also honor an explicit
        // drag-set `order` (fix: pinned reorder now persists).
        let orderA = oa?.order
        let orderB = ob?.order
        switch (orderA, orderB) {
        case let (.some(x), .some(y)):
            if x != y { return x < y }
            return a.startedAtKey > b.startedAtKey
        case (.none, .some):
            // Orderless (e.g. a brand-new session) sorts ABOVE ordered ones so
            // ADR-16 holds even AFTER a drag stamped the others.
            return true
        case (.some, .none):
            return false
        case (.none, .none):
            return a.startedAtKey > b.startedAtKey
        }
    }
}
