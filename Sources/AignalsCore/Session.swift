import Foundation

public struct Session: Equatable, Sendable {
    public let sessionID: String
    public let tool: String
    public let pid: Int32?
    public let projectName: String
    public let cwd: String?
    public let startedAt: Date
    /// Monotonic last-update timestamp of the session file (INV-8), parsed from
    /// the top-level `updated_at` ISO8601 field.
    public let updatedAt: Date
    /// Multi-status lifecycle state (schema v2, required field — ADR-10).
    public let state: SessionState
    public let currentAction: CurrentAction?

    public struct CurrentAction: Equatable, Sendable {
        public let tool: String
        public let target: String
        public let updatedAt: Date

        public init(tool: String, target: String, updatedAt: Date) {
            self.tool = tool
            self.target = target
            self.updatedAt = updatedAt
        }
    }

    public enum DecodeError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
        case missingField(String)
        case invalidDate(String)
    }

    public init(
        sessionID: String,
        tool: String,
        pid: Int32?,
        projectName: String,
        cwd: String?,
        startedAt: Date,
        updatedAt: Date,
        state: SessionState,
        currentAction: CurrentAction?
    ) {
        self.sessionID = sessionID
        self.tool = tool
        self.pid = pid
        self.projectName = projectName
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.state = state
        self.currentAction = currentAction
    }

    public static func decode(from data: Data) throws -> Session {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw DecodeError.missingField("root")
        }

        let version = dict["schema_version"] as? Int ?? 0
        guard version == 2 else { throw DecodeError.unsupportedSchemaVersion(version) }

        func required<T>(_ key: String) throws -> T {
            guard let v = dict[key] as? T else { throw DecodeError.missingField(key) }
            return v
        }

        let sessionID: String = try required("session_id")
        let tool: String = try required("tool")
        let projectName: String = try required("project_name")
        let startedAtStr: String = try required("started_at")
        guard let startedAt = isoDate(startedAtStr) else {
            throw DecodeError.invalidDate(startedAtStr)
        }

        // INV-8: monotonic last-update timestamp, required top-level `updated_at`.
        let updatedAtStr: String = try required("updated_at")
        guard let updatedAt = isoDate(updatedAtStr) else {
            throw DecodeError.invalidDate(updatedAtStr)
        }

        // ADR-10: `state` is a required field; missing/unknown -> decode fails.
        let stateStr: String = try required("state")
        guard let state = SessionState(jsonValue: stateStr) else {
            throw DecodeError.missingField("state")
        }

        let pid = (dict["pid"] as? Int).map(Int32.init) ?? (dict["pid"] as? Int32)
        let cwd = dict["cwd"] as? String

        let currentAction: CurrentAction?
        if let actionDict = dict["current_action"] as? [String: Any] {
            guard
                let aTool = actionDict["tool"] as? String,
                let aTarget = actionDict["target"] as? String,
                let aUpdatedStr = actionDict["updated_at"] as? String,
                let aUpdated = isoDate(aUpdatedStr)
            else { throw DecodeError.missingField("current_action") }
            currentAction = CurrentAction(tool: aTool, target: aTarget, updatedAt: aUpdated)
        } else {
            currentAction = nil
        }

        return Session(
            sessionID: sessionID,
            tool: tool,
            pid: pid,
            projectName: projectName,
            cwd: cwd,
            startedAt: startedAt,
            updatedAt: updatedAt,
            state: state,
            currentAction: currentAction
        )
    }
}

private let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func isoDate(_ s: String) -> Date? {
    iso.date(from: s)
}
