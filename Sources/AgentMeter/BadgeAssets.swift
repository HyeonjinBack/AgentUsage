import AppKit

enum ClaudeIconStyle: String, CaseIterable, Identifiable {
    case logo
    case clawd

    var id: String { rawValue }
    var title: String {
        switch self {
        case .logo: return "기본 로고"
        case .clawd: return "Clawd 마스코트"
        }
    }
    var image: NSImage? {
        switch self {
        case .logo: return BadgeAssets.claude
        case .clawd: return BadgeAssets.clawd ?? BadgeAssets.claude
        }
    }
}

enum BadgeAssets {
    static let codex = load("OpenAI")
    static let claude = load("Claude")
    static let clawd = load("Clawd")
    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
