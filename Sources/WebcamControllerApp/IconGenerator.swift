import AppKit

public enum IconGenerator {
    /// Creates a crisp macOS template webcam icon for the Menu Bar status item.
    @MainActor
    public static func makeMenuBarWebcamIcon() -> NSImage {
        if let sfImage = NSImage(
            systemSymbolName: "web.camera.fill",
            accessibilityDescription: "WebCam Controller"
        ) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            if let configured = sfImage.withSymbolConfiguration(config) {
                configured.isTemplate = true
                return configured
            }
            sfImage.isTemplate = true
            return sfImage
        }

        // Vector fallback webcam silhouette (template image)
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Outer webcam head circle
            let headRect = NSRect(x: 3.5, y: 5.5, width: 11, height: 11)
            let headPath = NSBezierPath(ovalIn: headRect)
            headPath.lineWidth = 1.6
            headPath.stroke()

            // Inner lens pupil
            let lensRect = NSRect(x: 7.0, y: 9.0, width: 4.0, height: 4.0)
            NSBezierPath(ovalIn: lensRect).fill()

            // Stand neck & base
            let base = NSBezierPath()
            base.lineWidth = 1.6
            base.lineCapStyle = .round
            base.move(to: NSPoint(x: 9, y: 5.2))
            base.line(to: NSPoint(x: 9, y: 2.5))
            base.move(to: NSPoint(x: 4.5, y: 2.2))
            base.line(to: NSPoint(x: 13.5, y: 2.2))
            base.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
}
