import AppKit

enum NodeBarIcon {
    static func image(for framework: NodeFramework, size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocusFlipped(false)

        let background = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
            xRadius: size * 0.22,
            yRadius: size * 0.22
        )
        color(for: framework).setFill()
        background.fill()

        let title = framework == .node ? "JS" : framework.displayName
        let fontSize = max(7, size * (title.count > 2 ? 0.27 : 0.40))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let titleSize = (title as NSString).size(withAttributes: attributes)
        let titleRect = NSRect(
            x: (size - titleSize.width) / 2,
            y: (size - titleSize.height) / 2 - 1,
            width: titleSize.width,
            height: titleSize.height
        )
        (title as NSString).draw(in: titleRect, withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func color(for framework: NodeFramework) -> NSColor {
        switch framework {
        case .node: return NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.31, alpha: 1)
        case .next: return NSColor(calibratedWhite: 0.08, alpha: 1)
        case .vite: return NSColor(calibratedRed: 0.40, green: 0.27, blue: 0.91, alpha: 1)
        case .nuxt: return NSColor(calibratedRed: 0.10, green: 0.63, blue: 0.43, alpha: 1)
        case .astro: return NSColor(calibratedRed: 0.88, green: 0.31, blue: 0.12, alpha: 1)
        }
    }
}
