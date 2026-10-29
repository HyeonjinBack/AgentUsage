import AppKit

enum BadgeAssets {
    static let codex = load("OpenAI")
    static let claude = load("Claude")
    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
