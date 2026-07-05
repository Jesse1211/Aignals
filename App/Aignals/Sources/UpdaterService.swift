import Foundation
import Observation
import Sparkle
import AignalsCore

/// Confines the Sparkle SDK to the app target. Drives our own silent probes
/// (Sparkle's built-in scheduler is disabled via Info.plist) and publishes an
/// UpdateState the UI reads. Only startUpdate() presents Sparkle's own UI.
@MainActor @Observable
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private(set) var state: UpdateState = .idle

    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private let driver: SPUStandardUserDriver

    override init() {
        driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                             userDriver: driver, delegate: nil)
        super.init()
        updater.delegate = self
        try? updater.start()
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    private var source: InstallSource {
        UpdateChecker.detectSource(bundlePath: Bundle.main.bundlePath)
    }

    /// Silent probe — no Sparkle UI. Feeds the badge/About state.
    func probe() {
        state = .checking
        updater.checkForUpdateInformation()
    }

    /// User clicked "Update Now" (direct installs) — presents Sparkle's dialog.
    func startUpdate() {
        updater.checkForUpdates()
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.state = UpdateChecker.state(current: self.currentVersion,
                                             latest: item.displayVersionString,
                                             source: self.source)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.state = .upToDate }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            // NOTE: `SUError.noUpdateError` is the expected case name in Sparkle 2.x,
            // but the exact rawValue or enum case name must be confirmed against the
            // pinned Sparkle version at compile time. If this line fails to compile,
            // the compiler error will name the correct case to use instead.
            if (error as NSError).code == Int(Sparkle.SUError.noUpdateError.rawValue) {
                self.state = .upToDate
            } else {
                self.state = .failed
            }
        }
    }
}
