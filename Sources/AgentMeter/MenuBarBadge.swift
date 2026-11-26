import AppKit

/// A template image preserves the two-line layout in NSStatusBar and follows its contrast/tint.
enum MenuBarBadge {
    struct Group {
        let session: String
        let weekly: String
        let icon: NSImage?
    }

    static func render(_ groups: [Group]) -> NSImage {
        let width = CGFloat(groups.count * 51 + max(0, groups.count - 1) * 16)
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            for (index, group) in groups.enumerated() {
                let x = CGFloat(index * 67)
                // Keep the original slot and percentage positions; shrink only the artwork.
                group.icon?.draw(in: NSRect(x: x + 1, y: 4, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1)
                for (text, y) in [(group.session, CGFloat(11)), (group.weekly, CGFloat(0))] {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                        .foregroundColor: NSColor.black
                    ]
                    let width = (text as NSString).size(withAttributes: attributes).width
                    (text as NSString).draw(at: NSPoint(x: x + 21 + (30 - width) / 2, y: y), withAttributes: attributes)
                }
                if index < groups.count - 1 {
                    NSColor.black.withAlphaComponent(0.4).setStroke()
                    let divider = NSBezierPath()
                    divider.move(to: NSPoint(x: x + 55, y: 4))
                    divider.line(to: NSPoint(x: x + 61, y: 18))
                    divider.lineWidth = 0.7
                    divider.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "위 세션, 아래 주간 잔여 한도"
        return image
    }
}
