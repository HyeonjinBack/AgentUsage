import AppKit

/// A template image preserves the two-line layout in NSStatusBar and follows its contrast/tint.
enum MenuBarBadge {
    static func render(codexSession: String, codexWeekly: String, claudeSession: String, claudeWeekly: String,
                       codexIcon: NSImage?, claudeIcon: NSImage?) -> NSImage {
        let image = NSImage(size: NSSize(width: 118, height: 22), flipped: false) { _ in
            func group(icon: NSImage?, x: CGFloat, session: String, weekly: String) {
                icon?.draw(in: NSRect(x: x, y: 3, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1)
                for (text, y) in [(session, CGFloat(11)), (weekly, CGFloat(0))] {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                        .foregroundColor: NSColor.black
                    ]
                    let width = (text as NSString).size(withAttributes: attributes).width
                    (text as NSString).draw(at: NSPoint(x: x + 21 + (30 - width) / 2, y: y), withAttributes: attributes)
                }
            }
            group(icon: codexIcon, x: 0, session: codexSession, weekly: codexWeekly)
            group(icon: claudeIcon, x: 67, session: claudeSession, weekly: claudeWeekly)
            NSColor.black.withAlphaComponent(0.4).setStroke()
            let divider = NSBezierPath()
            divider.move(to: NSPoint(x: 55, y: 4)); divider.line(to: NSPoint(x: 61, y: 18))
            divider.lineWidth = 0.7; divider.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Codex와 Claude: 위 세션, 아래 주간 잔여 한도"
        return image
    }
}
