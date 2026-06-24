import Foundation

public struct AignalsConfig: Equatable, Codable, Sendable {
    public var launchAtLogin: Bool
    public var dismissedInstallPrompt: Bool
    /// Global sound toggle (ADR-20). Decodes to `true` when the key is absent so
    /// existing config.json files keep sound on after upgrade.
    public var soundEnabled: Bool
    /// Selected visual theme (ADR-0810). Decodes to `.glassDark` when the key is
    /// absent so existing config.json files land on the default after upgrade.
    public var theme: Theme

    public init(launchAtLogin: Bool, dismissedInstallPrompt: Bool, soundEnabled: Bool = true, theme: Theme = .glassDark) {
        self.launchAtLogin = launchAtLogin
        self.dismissedInstallPrompt = dismissedInstallPrompt
        self.soundEnabled = soundEnabled
        self.theme = theme
    }

    public static let `default` = AignalsConfig(launchAtLogin: false, dismissedInstallPrompt: false, soundEnabled: true, theme: .glassDark)

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case dismissedInstallPrompt
        case soundEnabled
        case theme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        self.dismissedInstallPrompt = try container.decode(Bool.self, forKey: .dismissedInstallPrompt)
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .glassDark
    }
}

public final class ConfigStore {
    private let paths: Paths
    public private(set) var config: AignalsConfig

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.configFile),
           let decoded = try? JSONDecoder().decode(AignalsConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    public func save(_ next: AignalsConfig) {
        config = next
        try? paths.ensureDirectories()
        let tmp = paths.configFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? JSONEncoder().encode(next) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.configFile, withItemAt: tmp)
        }
    }
}
