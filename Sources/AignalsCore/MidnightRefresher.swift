import Foundation

/// Pure helpers for "did we cross local midnight?" so the daily-quote refresh
/// can be driven off the UI's existing tick without a live timer in tests.
/// No session coupling.
public struct MidnightRefresher {
    /// The next local 00:00 strictly after `date`.
    public static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    /// True iff `last` and `now` fall on different calendar days (local time).
    public static func didCrossMidnight(from last: Date, to now: Date, calendar: Calendar) -> Bool {
        !calendar.isDate(last, inSameDayAs: now)
    }
}
