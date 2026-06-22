import AppKit

public enum StatusIcon {
    /// Render the menu-bar dot from the derived multi-status counts plus the
    /// FS-access health flag (ADR-3/ADR-9). Preserves the old colour mapping:
    /// any active session → red ("running"), none → green ("idle"),
    /// FS-access error → gray hollow ring.
    public static func image(for counts: StatusCounts, hasError: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let dotRect = NSRect(x: 4, y: 4, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: dotRect)
            if hasError {
                NSColor.systemGray.setFill()
            } else if counts.isEmpty {
                NSColor.systemGreen.setFill()
            } else {
                NSColor.systemRed.setFill()
            }
            path.fill()

            if hasError {
                // inner hollow ring to distinguish error from a generic gray dot
                NSColor.black.setStroke()
                let inner = NSBezierPath(ovalIn: dotRect.insetBy(dx: 2, dy: 2))
                inner.lineWidth = 1.5
                inner.stroke()
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}
