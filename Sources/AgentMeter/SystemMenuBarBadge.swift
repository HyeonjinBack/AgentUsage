import AppKit

enum SystemMenuBarBadge {
    static let width: CGFloat = 160
    static let warningThreshold = 0.8

    static func render(cpu: Double?, memoryUsed: Double?, memoryTotal: Double?, foreground: NSColor) -> NSImage {
        let cpuFraction = cpu.flatMap { $0.isFinite ? min(1, max(0, $0 / 100)) : nil }
        let memoryFraction: Double? = {
            guard let used = memoryUsed, let total = memoryTotal,
                  used.isFinite, total.isFinite, used >= 0, total > 0 else { return nil }
            return min(1, max(0, used / total))
        }()
        let cpuText = cpuFraction.map { String(format: "CPU %.0f%%", $0 * 100) } ?? "CPU —"
        let memoryText = memoryFraction.flatMap { _ in memoryUsed }.map { String(format: "Mem %.1fG", $0 / 1e9) } ?? "Mem —"
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            func metric(symbol: String, iconX: CGFloat, textX: CGFloat, trackWidth: CGFloat, title: String, value: Double?) {
                let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                if let icon {
                    tinted(icon, color: foreground).draw(in: NSRect(x: iconX, y: 4, width: 14, height: 14))
                }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
                    .foregroundColor: foreground
                ]
                (title as NSString).draw(at: NSPoint(x: textX, y: 10), withAttributes: attributes)
                let track = NSRect(x: textX, y: 4, width: trackWidth, height: 2)
                foreground.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
                if let value, value > 0 {
                    (value >= warningThreshold ? NSColor.systemRed : foreground.withAlphaComponent(0.85)).setFill()
                    let fill = NSRect(x: track.minX, y: track.minY, width: track.width * value, height: track.height)
                    NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
                }
            }
            metric(symbol: "cpu", iconX: 0, textX: 19, trackWidth: 45, title: cpuText, value: cpuFraction)
            metric(symbol: "memorychip", iconX: 76, textX: 95, trackWidth: 64, title: memoryText, value: memoryFraction)
            return true
        }
        image.isTemplate = false // Preserve the red gauge fill.
        return image
    }

    static func combine(ai: NSImage, system: NSImage, foreground: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: ai.size.width + 12 + width, height: 22), flipped: false) { _ in
            tinted(ai, color: foreground).draw(in: NSRect(origin: .zero, size: ai.size))
            foreground.withAlphaComponent(0.3).setStroke()
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: ai.size.width + 5, y: 4))
            separator.line(to: NSPoint(x: ai.size.width + 5, y: 18))
            separator.lineWidth = 0.7; separator.stroke()
            system.draw(in: NSRect(x: ai.size.width + 12, y: 0, width: width, height: 22))
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func tinted(_ source: NSImage, color: NSColor) -> NSImage {
        NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill(); rect.fill(using: .sourceIn)
            return true
        }
    }
}
