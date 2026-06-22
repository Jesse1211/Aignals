import AppKit

public enum StatusIcon {
    // Layout constants (points). Each visible group is a colored dot followed by
    // its count digits, laid out left-to-right. Groups with a count of 0 are
    // omitted entirely (INV-5/ADR-11), which makes the rendered width shrink by
    // exactly one group's worth — this is the deterministic size difference the
    // tests assert on.
    private static let height: CGFloat = 18
    private static let dotDiameter: CGFloat = 10
    private static let dotTextGap: CGFloat = 2
    private static let groupGap: CGFloat = 4
    private static let edgePadding: CGFloat = 4
    private static let digitWidth: CGFloat = 7   // approx advance per digit
    private static let countFontSize: CGFloat = 11

    /// A single (color, count) group to render. Order is fixed:
    /// red = working, yellow = waitingPermission, green = waitingInput.
    private struct Group {
        let color: NSColor
        let count: Int
    }

    private static func groups(for counts: StatusCounts) -> [Group] {
        // Build all three then drop the zero-count ones (ADR-11 / INV-5).
        let all = [
            Group(color: .systemRed, count: counts.working),
            Group(color: .systemYellow, count: counts.waitingPermission),
            Group(color: .systemGreen, count: counts.waitingInput),
        ]
        return all.filter { $0.count > 0 }
    }

    private static func digitCount(_ n: Int) -> Int {
        // n is always >= 1 here (zero groups are omitted).
        return String(n).count
    }

    private static func groupWidth(_ g: Group) -> CGFloat {
        dotDiameter + dotTextGap + CGFloat(digitCount(g.count)) * digitWidth
    }

    /// Render the menu-bar label from the derived multi-status counts plus the
    /// FS-access health flag (ADR-3/ADR-9/ADR-11).
    ///
    /// - When `hasError` is true, the gray error dot + ring is rendered and takes
    ///   precedence over the counts.
    /// - Otherwise, a colored dot + count is drawn for each non-empty group,
    ///   left-to-right: red (working), yellow (waitingPermission),
    ///   green (waitingInput). Zero-count groups are omitted (INV-5/ADR-11), so
    ///   the image width shrinks for each absent group.
    /// - When all counts are zero (no sessions), a single dim neutral dot is drawn.
    ///
    /// `isTemplate` stays `false` so the colors persist across light/dark mode.
    public static func image(for counts: StatusCounts, hasError: Bool) -> NSImage {
        if hasError {
            return errorImage()
        }

        let visible = groups(for: counts)
        if visible.isEmpty {
            return emptyImage()
        }

        // Total width = edge padding on both sides + each group's width +
        // a gap between adjacent groups.
        let groupsWidth = visible.map(groupWidth).reduce(0, +)
        let gapsWidth = groupGap * CGFloat(max(0, visible.count - 1))
        let width = edgePadding * 2 + groupsWidth + gapsWidth

        let size = NSSize(width: width, height: height)
        let img = NSImage(size: size, flipped: false) { _ in
            var x = edgePadding
            let dotY = (height - dotDiameter) / 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: countFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            for g in visible {
                // Dot.
                let dotRect = NSRect(x: x, y: dotY, width: dotDiameter, height: dotDiameter)
                g.color.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                x += dotDiameter + dotTextGap

                // Count.
                let text = String(g.count) as NSString
                let textWidth = CGFloat(digitCount(g.count)) * digitWidth
                let textSize = text.size(withAttributes: attrs)
                let textY = (height - textSize.height) / 2
                text.draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
                x += textWidth + groupGap
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Gray hollow error dot — fixed square size, unaffected by counts.
    private static func errorImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let dotRect = NSRect(x: 4, y: 4, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: dotRect)
            NSColor.systemGray.setFill()
            path.fill()
            // inner hollow ring to distinguish error from a generic gray dot
            NSColor.black.setStroke()
            let inner = NSBezierPath(ovalIn: dotRect.insetBy(dx: 2, dy: 2))
            inner.lineWidth = 1.5
            inner.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Neutral empty state when there are no sessions: a single dim dot.
    private static func emptyImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let dotRect = NSRect(x: 4, y: 4, width: 10, height: 10)
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}
