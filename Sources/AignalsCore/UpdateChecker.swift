import Foundation

public enum InstallSource: Equatable, Sendable { case direct, homebrew }

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String, source: InstallSource)
    case failed
}

/// Pure version/source logic. No Sparkle, no I/O — fully unit-testable.
public struct UpdateChecker {
    /// True when `latest` is strictly newer than `current` (numeric, dot-separated).
    public static func compare(current: String, latest: String) -> Bool {
        let a = current.split(separator: ".").map { Int($0) ?? 0 }
        let b = latest.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if y != x { return y > x }
        }
        return false
    }

    /// Homebrew cask installs live under a `/Caskroom/` path (or symlink into one).
    public static func detectSource(bundlePath: String) -> InstallSource {
        bundlePath.contains("/Caskroom/") ? .homebrew : .direct
    }

    public static func state(current: String, latest: String?, source: InstallSource) -> UpdateState {
        guard let latest else { return .failed }
        return compare(current: current, latest: latest)
            ? .available(version: latest, source: source)
            : .upToDate
    }
}
