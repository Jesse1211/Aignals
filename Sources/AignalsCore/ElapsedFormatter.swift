import Foundation

public enum ElapsedFormatter {
    public static func format(seconds: TimeInterval) -> String {
        let s = Int(seconds)
        switch s {
        case ..<60:           return "\(s)s"
        case ..<3600:         return "\(s / 60)m"
        case ..<86_400:       return "\(s / 3600)h"
        default:              return "\(s / 86_400)d"
        }
    }

    public static func format(from start: Date, to now: Date = Date()) -> String {
        format(seconds: now.timeIntervalSince(start))
    }
}
