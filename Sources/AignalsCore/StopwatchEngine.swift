import Foundation

public struct SealedSegment: Equatable, Sendable {
    public let day: String
    public let segment: WorkSegment
    public init(day: String, segment: WorkSegment) {
        self.day = day
        self.segment = segment
    }
}

/// Pure stopwatch state machine + wall-clock math + local-midnight cut. No I/O,
/// no bare Date(): every entry point takes now and calendar so all time
/// logic is unit-testable with a fake clock. No session coupling.
public struct StopwatchEngine {
    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func displaySeconds(_ snap: StopwatchSnapshot, now: Date) -> Int {
        guard snap.phase == .running, let start = snap.currentSegmentStart else {
            return snap.accumulatedSeconds
        }
        return snap.accumulatedSeconds + max(0, Int(now.timeIntervalSince(start)))
    }

    public func start(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .idle else { return (snap, []) }
        return (StopwatchSnapshot(phase: .running, day: Self.dayKey(now, calendar: calendar),
                                  accumulatedSeconds: 0, currentSegmentStart: now), [])
    }

    public func stop(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .running, let start = snap.currentSegmentStart else { return (snap, []) }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let seg = SealedSegment(day: snap.day ?? Self.dayKey(start, calendar: calendar),
                                segment: WorkSegment(start: start, end: now, seconds: seconds))
        var next = snap
        next.phase = .stopped
        next.accumulatedSeconds += seconds
        next.currentSegmentStart = nil
        return (next, [seg])
    }

    public func resume(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .stopped else { return (snap, []) }
        var next = snap
        next.phase = .running
        next.currentSegmentStart = now
        return (next, [])
    }

    public func end(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        var sealed: [SealedSegment] = []
        if snap.phase == .running, let start = snap.currentSegmentStart {
            let seconds = max(0, Int(now.timeIntervalSince(start)))
            sealed.append(SealedSegment(day: snap.day ?? Self.dayKey(start, calendar: calendar),
                                        segment: WorkSegment(start: start, end: now, seconds: seconds)))
        } else if snap.phase == .idle {
            return (snap, [])
        }
        return (StopwatchSnapshot.idle, sealed)
    }

    public func evaluate(_ snap: StopwatchSnapshot, now: Date, calendar: Calendar)
        -> (StopwatchSnapshot, [SealedSegment]) {
        guard snap.phase == .running, let start = snap.currentSegmentStart else { return (snap, []) }
        let startDay = Self.dayKey(start, calendar: calendar)
        guard startDay != Self.dayKey(now, calendar: calendar) else { return (snap, []) }
        let startOfStartDay = calendar.startOfDay(for: start)
        let cutEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfStartDay) ?? start
        let seconds = max(0, Int(cutEnd.timeIntervalSince(start)))
        let seg = SealedSegment(day: startDay,
                                segment: WorkSegment(start: start, end: cutEnd, seconds: seconds))
        let next = StopwatchSnapshot(phase: .stopped, day: Self.dayKey(now, calendar: calendar),
                                     accumulatedSeconds: 0, currentSegmentStart: nil)
        return (next, [seg])
    }

    public static func canStart(_ p: StopwatchPhase) -> Bool { p == .idle }
    public static func canStop(_ p: StopwatchPhase) -> Bool { p == .running }
    public static func canResume(_ p: StopwatchPhase) -> Bool { p == .stopped }
    public static func canEnd(_ p: StopwatchPhase) -> Bool { p == .running || p == .stopped }
}
