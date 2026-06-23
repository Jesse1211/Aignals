import Foundation

/// App-owned per-session user preferences (side-car overlay, INV-9).
///
/// This value object is persisted by `OverrideStore` to `~/.aignals/overrides.json`,
/// keyed by `session_id`, and merged onto a `Session` at read time. It is SEPARATE
/// from the hook-owned session files: the hook never touches overrides.
///
/// - `name`: user-chosen display name; effective name = `name ?? projectName` (ADR-18).
/// - `order`: user-chosen sort position (ADR-16).
/// - `pinned`: "ping"/pin flag keeping a row on top (ADR-19); defaults to false.
/// - `muted`: per-session mute flag suppressing this session's sound (ADR-20);
///   defaults to false and decodes to false when absent for back-compat.
public struct SessionOverride: Equatable, Sendable, Codable {
    public var name: String?
    public var order: Int?
    public var pinned: Bool
    public var muted: Bool

    public init(name: String? = nil, order: Int? = nil, pinned: Bool = false, muted: Bool = false) {
        self.name = name
        self.order = order
        self.pinned = pinned
        self.muted = muted
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case order
        case pinned
        case muted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.order = try container.decodeIfPresent(Int.self, forKey: .order)
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        self.muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}
