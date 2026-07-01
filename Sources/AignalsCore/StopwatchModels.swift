import Foundation

public enum StopwatchPhase: String, Codable, Sendable { case idle, running, stopped }

/// Persisted volatile running state (stopwatch-state.json payload).
public struct StopwatchSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var phase: StopwatchPhase
    public var day: String?
    public var accumulatedSeconds: Int
    public var currentSegmentStart: Date?
    public init(version: Int = 1, phase: StopwatchPhase = .idle, day: String? = nil,
                accumulatedSeconds: Int = 0, currentSegmentStart: Date? = nil) {
        self.version = version
        self.phase = phase
        self.day = day
        self.accumulatedSeconds = accumulatedSeconds
        self.currentSegmentStart = currentSegmentStart
    }
    public static let idle = StopwatchSnapshot()
}

/// One sealed work span.
public struct WorkSegment: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let seconds: Int
    public init(start: Date, end: Date, seconds: Int) {
        self.start = start
        self.end = end
        self.seconds = seconds
    }
}

/// A day's sealed segments + redundant total.
public struct WorkDay: Codable, Equatable, Sendable {
    public var totalSeconds: Int
    public var segments: [WorkSegment]
    public init(totalSeconds: Int = 0, segments: [WorkSegment] = []) {
        self.totalSeconds = totalSeconds
        self.segments = segments
    }
}
