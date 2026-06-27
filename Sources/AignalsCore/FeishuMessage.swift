import Foundation

/// Builds the plain-text body Aignals pushes to a Feishu custom bot on a 🟡/🟢
/// transition. Pure (no networking) so it is unit-tested; the App target passes
/// the session's effective display name (honoring renames) and the configured
/// keyword. States that never alert (working/disconnected) return `nil`, mirroring
/// `AppViewModel.sound(forTransitionInto:)`.
public enum FeishuMessage {
    /// The message for a transition INTO `state`, or `nil` for non-alerting states.
    ///
    /// Every message begins with the literal `Aignals`. If `keyword` is non-empty
    /// and the text does not already contain it (Feishu keyword-mode requires a
    /// literal-substring match), ` [<keyword>]` is appended so the bot accepts it.
    public static func text(displayName: String, state: SessionState, keyword: String = "") -> String? {
        let body: String
        switch state {
        case .waitingPermission:
            body = "Aignals • \(displayName): 🟡 waiting for permission — go click Allow"
        case .waitingInput:
            body = "Aignals • \(displayName): 🟢 finished — your turn"
        case .working, .disconnected:
            return nil
        }
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if kw.isEmpty || body.contains(kw) { return body }
        return body + " [\(kw)]"
    }
}
