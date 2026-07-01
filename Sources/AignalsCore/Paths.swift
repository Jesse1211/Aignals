import Foundation

public struct Paths: Sendable {
    public let home: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let override = environment["AIGNALS_HOME"], !override.isEmpty {
            self.home = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".aignals", isDirectory: true)
        }
    }

    public var sessionsDirectory: URL {
        home.appendingPathComponent("sessions", isDirectory: true)
    }

    public var configFile: URL {
        home.appendingPathComponent("config.json")
    }

    public var overridesFile: URL {
        home.appendingPathComponent("overrides.json")
    }

    public var quotesFile: URL {
        home.appendingPathComponent("quotes.json")
    }

    public func sessionFile(id: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(id).json")
    }

    /// Ensure home and sessions dir exist with mode 0700. Idempotent.
    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [home, sessionsDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }
}
