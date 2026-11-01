import AppKit

/// A solid rounded square with the heartbeat cut out of it, so the menu bar shows through the line,
/// plus a health dot on its bottom-right corner.
enum MenuBarIcon {
    // Sized to sit level with typical menu bar icons (about 15 pt tall).
    private static let screen = NSRect(x: 0, y: 3, width: 15, height: 15)
    // A narrow side inset keeps the heartbeat wide enough to read its peaks.
    private static let trace = screen.insetBy(dx: 1.5, dy: 3)
    /// Just inside the screen's bottom-right corner, clear of the heartbeat.
    private static let badge = NSRect(x: 10, y: 0.5, width: 7.5, height: 7.5)
    /// The menu bar centers the whole image, so pad the top as much as the badge hangs below
    /// to keep the screen itself level with neighboring icons.
    private static let size = NSSize(width: badge.maxX, height: screen.maxY + screen.minY)

    /// One heartbeat (x and y from 0 to 1): flat, P bump, sharp QRS spike, T wave, flat.
    private static let beat: [CGPoint] = [
        (0, 0.42), (0.13, 0.42), (0.2, 0.55), (0.27, 0.42), (0.33, 0.42), (0.37, 0.28),
        (0.45, 1), (0.53, 0), (0.59, 0.42), (0.67, 0.42), (0.77, 0.66), (0.87, 0.42), (1, 0.42),
    ].map { CGPoint(x: trace.minX + $0.0 * trace.width, y: trace.minY + $0.1 * trace.height) }

    /// Brighter on a dark menu bar, deeper on a light one, so the dot stands out on both.
    private static let green = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.3, green: 0.9, blue: 0.5, alpha: 1)
            : NSColor(srgbRed: 0.08, green: 0.62, blue: 0.26, alpha: 1)
    }

    static func image(for health: Health) -> NSImage {
        let dotColor: NSColor = switch health {
        case .green: green
        case .amber: .systemOrange
        case .red: .systemRed
        }
        // The colored dot means this can't be a template image, so the square is drawn
        // in labelColor at draw time to follow the menu bar's light/dark appearance.
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.labelColor.withAlphaComponent(1).setFill()
            NSBezierPath(roundedRect: screen, xRadius: 3.75, yRadius: 3.75).fill()

            let line = NSBezierPath()
            line.move(to: beat[0])
            beat.dropFirst().forEach { line.line(to: $0) }
            line.lineWidth = 1.3
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            NSColor.clear.setStroke()
            NSColor.clear.setFill()
            cuttingOut {
                line.stroke()
                NSBezierPath(ovalIn: badge.insetBy(dx: -1.25, dy: -1.25)).fill()
            }

            dotColor.setFill()
            NSBezierPath(ovalIn: badge).fill()
            return true
        }
        image.accessibilityDescription = "Mac Monitor"
        return image
    }

    private static func cuttingOut(_ draw: () -> Void) {
        NSGraphicsContext.current?.compositingOperation = .copy
        draw()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
