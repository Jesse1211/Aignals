import AppKit

public enum StatusIcon {
    public static func image(for status: AggregateStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let dotRect = NSRect(x: 4, y: 4, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: dotRect)
            switch status {
            case .running: NSColor.systemRed.setFill()
            case .idle:    NSColor.systemGreen.setFill()
            case .error:   NSColor.systemGray.setFill()
            }
            path.fill()

            if status == .error {
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
