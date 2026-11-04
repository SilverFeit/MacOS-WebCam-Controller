import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import UVCCore

// MARK: - High-DPI App Icon & Documentation Screenshot Renderer

@MainActor
enum DocAssetRenderer {
    static func generateAllAssets(outputDirectory: String) throws {
        let outURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        // Ensure AppKit GUI context is initialized offscreen without stealing focus
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        // 1. Render 512x512 App Icon PNG
        if let iconRep = renderHighDetailAppIcon(size: 512),
           let png = iconRep.representation(using: .png, properties: [:]) {
            try png.write(to: outURL.appendingPathComponent("app-icon.png"))
            print("Saved app-icon.png")
        }

        // 2. Initialize CameraManager with deterministic UVC 2K/60fps showcase profile for crisp documentation screenshots
        let suiteName = "com.webcamcontroller.docrender.\(UUID().uuidString)"
        let tempDefaults = UserDefaults(suiteName: suiteName)!
        defer { tempDefaults.removePersistentDomain(forName: suiteName) }

        let manager = CameraManager(
            defaults: tempDefaults,
            enableHotplugWatcher: false,
            enableBackgroundMonitors: false
        )
        defer { manager.shutdown() }

        manager.loadDocumentationShowcaseCamera()
        manager.isHardwareLockEnabled = true
        _ = manager.saveCurrentSettingsAsPreset(name: "Studio Daylight", loadAtStart: true)
        manager.statusMessage = "Direct Endpoint 0 UVC active · 0% video CPU overhead"

        // Capture individual window cards at @2x Retina
        manager.activePanelTab = .basic
        let basicWindowCard = renderFramedWindowView(
            title: "Webcam Settings Panel",
            width: 472,
            height: 716
        ) {
            WebcamSettingsPanelView(manager: manager)
        }

        manager.activePanelTab = .advanced
        let advancedWindowCard = renderFramedWindowView(
            title: "Webcam Settings Panel",
            width: 472,
            height: 716
        ) {
            WebcamSettingsPanelView(manager: manager)
        }

        manager.activePanelTab = .preferences
        let preferencesWindowCard = renderFramedWindowView(
            title: "Webcam Settings Panel",
            width: 472,
            height: 716
        ) {
            WebcamSettingsPanelView(manager: manager)
        }

        let menuBarCard = renderSwiftUICard(width: 438, height: 690) {
            MenuBarShowcaseCardView(manager: manager)
        }

        // 3. Save side-by-side Basic + Advanced Panel showcase
        if let basicImg = basicWindowCard,
           let advImg = advancedWindowCard,
           let pairRep = renderSideBySideShowcase(
               leftImage: basicImg,
               leftCaption: "Basic Tab — Exposure, Shutter, ISP Color & Kelvin White Balance",
               rightImage: advImg,
               rightCaption: "Advanced Tab — 2K/4K Resolution, Validated FPS, Anti-Flicker & Rollback",
               canvasSize: CGSize(width: 1080, height: 830)
           ),
           let png = pairRep.representation(using: .png, properties: [:]) {
            try png.write(to: outURL.appendingPathComponent("panel-basic-advanced.png"))
            print("Saved panel-basic-advanced.png")
        }

        // 4. Save side-by-side Menu Bar Popover + Preferences Tab showcase
        if let menuImg = menuBarCard,
           let prefImg = preferencesWindowCard,
           let menuPrefRep = renderSideBySideShowcase(
               leftImage: menuImg,
               leftCaption: "Menu Bar Popover — Instant One-Click Hardware Controls",
               rightImage: prefImg,
               rightCaption: "Preferences Tab — USB Hardware ID Binding & Anti-Reset Lock",
               canvasSize: CGSize(width: 1080, height: 830)
           ),
           let png = menuPrefRep.representation(using: .png, properties: [:]) {
            try png.write(to: outURL.appendingPathComponent("menubar-and-preferences.png"))
            print("Saved menubar-and-preferences.png")
        }

        // 5. Save Hero Banner (1280x680 logical -> 2560x1360 @2x Retina)
        if let iconImg = renderHighDetailAppIcon(size: 256).flatMap({ nsImage(from: $0) }),
           let menuImg = menuBarCard,
           let basicImg = basicWindowCard,
           let advImg = advancedWindowCard,
           let heroRep = renderHeroBanner(
               icon: iconImg,
               menuCard: menuImg,
               basicCard: basicImg,
               advancedCard: advImg,
               canvasSize: CGSize(width: 1280, height: 690)
           ),
           let png = heroRep.representation(using: .png, properties: [:]) {
            try png.write(to: outURL.appendingPathComponent("hero-banner.png"))
            print("Saved hero-banner.png")
        }
    }

    // MARK: - Offscreen Retina NSView / SwiftUI Rendering Helpers

    private static func renderFramedWindowView<Content: View>(
        title: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> NSImage? {
        let totalHeight = height + 30
        return renderSwiftUICard(width: width, height: totalHeight) {
            VStack(spacing: 0) {
                // Classic macOS Window Titlebar
                ZStack {
                    LinearGradient(
                        colors: [Color(white: 0.96), Color(white: 0.91)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 11.5, height: 11.5)
                        Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18)).frame(width: 11.5, height: 11.5)
                        Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 11.5, height: 11.5)
                        Spacer()
                    }
                    .padding(.leading, 12)

                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.78))
                }
                .frame(height: 30)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
                }

                content()
                    .frame(width: width, height: height)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private static func renderSwiftUICard<Content: View>(
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> NSImage? {
        let root = content()
            .environment(\.colorScheme, .light)
            .frame(width: width, height: height)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting

        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.10))
        hosting.layoutSubtreeIfNeeded()

        let scale: Int = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width) * scale,
            pixelsHigh: Int(height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = NSSize(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        window.contentView = nil
        return nsImage(from: rep)
    }

    private static func nsImage(from rep: NSBitmapImageRep) -> NSImage {
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    // MARK: - Side-by-Side Retina Canvas Compositor

    private static func renderSideBySideShowcase(
        leftImage: NSImage,
        leftCaption: String,
        rightImage: NSImage,
        rightCaption: String,
        canvasSize: CGSize
    ) -> NSBitmapImageRep? {
        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width) * scale,
            pixelsHigh: Int(canvasSize.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = canvasSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext

        drawDarkCanvasBackground(cg: cg, size: canvasSize, cornerRadius: 20)

        let topMargin: CGFloat = 28
        let maxCardH = canvasSize.height - 86
        let colW = (canvasSize.width - 78) / 2.0

        drawShadowedImage(
            leftImage,
            in: CGRect(x: 26, y: canvasSize.height - topMargin - maxCardH, width: colW, height: maxCardH),
            cg: cg
        )
        drawShadowedImage(
            rightImage,
            in: CGRect(x: 26 + colW + 26, y: canvasSize.height - topMargin - maxCardH, width: colW, height: maxCardH),
            cg: cg
        )

        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.90, alpha: 1.0)
        ]
        drawCenteredText(leftCaption, attrs: captionAttrs, centerX: 26 + colW / 2, y: 20)
        drawCenteredText(rightCaption, attrs: captionAttrs, centerX: 26 + colW + 26 + colW / 2, y: 20)

        return rep
    }

    // MARK: - Hero Banner Compositor

    private static func renderHeroBanner(
        icon: NSImage,
        menuCard: NSImage,
        basicCard: NSImage,
        advancedCard: NSImage,
        canvasSize: CGSize
    ) -> NSBitmapImageRep? {
        let scale = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width) * scale,
            pixelsHigh: Int(canvasSize.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = canvasSize

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext

        drawDarkCanvasBackground(cg: cg, size: canvasSize, cornerRadius: 24)

        // Subtle glowing cyan & emerald ambient orbs
        let cs = CGColorSpaceCreateDeviceRGB()
        if let cyanGlow = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(red: 0.08, green: 0.55, blue: 0.95, alpha: 0.25),
                CGColor(red: 0.08, green: 0.55, blue: 0.95, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawRadialGradient(
                cyanGlow,
                startCenter: CGPoint(x: 240, y: canvasSize.height - 130),
                startRadius: 0,
                endCenter: CGPoint(x: 240, y: canvasSize.height - 130),
                endRadius: 340,
                options: []
            )
        }
        if let emeraldGlow = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(red: 0.10, green: 0.78, blue: 0.54, alpha: 0.20),
                CGColor(red: 0.10, green: 0.78, blue: 0.54, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawRadialGradient(
                emeraldGlow,
                startCenter: CGPoint(x: 1020, y: 240),
                startRadius: 0,
                endCenter: CGPoint(x: 1020, y: 240),
                endRadius: 380,
                options: []
            )
        }

        // Left Column: Icon + Title + Subtitle + Feature Pills
        let leftX: CGFloat = 54
        let iconRect = NSRect(x: leftX, y: canvasSize.height - 148, width: 92, height: 92)
        icon.draw(in: iconRect)

        let badgePillRect = CGRect(x: leftX, y: canvasSize.height - 190, width: 288, height: 26)
        let badgePath = CGPath(roundedRect: badgePillRect, cornerWidth: 13, cornerHeight: 13, transform: nil)
        cg.setFillColor(CGColor(red: 0.07, green: 0.36, blue: 0.29, alpha: 0.75))
        cg.addPath(badgePath)
        cg.fillPath()
        cg.setStrokeColor(CGColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 0.65))
        cg.setLineWidth(1.0)
        cg.addPath(badgePath)
        cg.strokePath()

        let pillTextAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.68, green: 0.96, blue: 0.84, alpha: 1.0)
        ]
        NSString(string: "NATIVE USB UVC · ZERO VIRTUAL CAMERAS").draw(
            at: NSPoint(x: leftX + 14, y: canvasSize.height - 184),
            withAttributes: pillTextAttrs
        )

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        NSString(string: "MacOS WebCam").draw(at: NSPoint(x: leftX, y: canvasSize.height - 246), withAttributes: titleAttrs)
        NSString(string: "Controller").draw(at: NSPoint(x: leftX, y: canvasSize.height - 290), withAttributes: titleAttrs)

        let subtitlePara = NSMutableParagraphStyle()
        subtitlePara.lineSpacing = 4
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.78, green: 0.83, blue: 0.90, alpha: 1.0),
            .paragraphStyle: subtitlePara
        ]
        let subText = "Control physical USB webcam sensor & ISP registers directly from the macOS Menu Bar over IOKit Endpoint 0 — while Zoom, OBS, Teams, or Meet stream untouched native video."
        NSString(string: subText).draw(
            in: NSRect(x: leftX, y: canvasSize.height - 404, width: 396, height: 96),
            withAttributes: subAttrs
        )

        let bullets = [
            "✓  Exposure, 1/60s Shutter, Kelvin & ISP Color",
            "✓  2K / 4K Resolutions, Validated FPS & 5fps Call Fix",
            "✓  Punctual Rollback (↺) & Anti-Reset Hardware Lock",
            "✓  Homebrew Cask + Full `webcamctl` CLI Automation",
            "✓  0% Video CPU Overhead · Zero Camera/Mic Prompts"
        ]
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.98, alpha: 1.0)
        ]
        for (idx, line) in bullets.enumerated() {
            NSString(string: line).draw(
                at: NSPoint(x: leftX, y: canvasSize.height - 448 - CGFloat(idx) * 29),
                withAttributes: bulletAttrs
            )
        }

        // Right Showcase Stack: Back Basic Window + Middle Menu Bar Card + Front Advanced Window
        drawShadowedImage(
            menuCard,
            in: CGRect(x: 468, y: 54, width: 332, height: 525),
            cg: cg
        )
        drawShadowedImage(
            basicCard,
            in: CGRect(x: 682, y: 92, width: 356, height: 556),
            cg: cg
        )
        drawShadowedImage(
            advancedCard,
            in: CGRect(x: 878, y: 34, width: 368, height: 576),
            cg: cg
        )

        return rep
    }

    private static func drawDarkCanvasBackground(cg: CGContext, size: CGSize, cornerRadius: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        cg.saveGState()
        cg.addPath(path)
        cg.clip()

        let cs = CGColorSpaceCreateDeviceRGB()
        if let grad = CGGradient(
            colorsSpace: cs,
            colors: [
                CGColor(red: 0.08, green: 0.11, blue: 0.18, alpha: 1.0),
                CGColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: size.width, y: 0),
                options: []
            )
        }
        cg.restoreGState()

        cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
        cg.setLineWidth(1.5)
        cg.addPath(path)
        cg.strokePath()
    }

    private static func drawShadowedImage(_ image: NSImage, in targetRect: CGRect, cg: CGContext) {
        let imgSize = image.size
        guard imgSize.width > 0 && imgSize.height > 0 else { return }
        let scale = min(targetRect.width / imgSize.width, targetRect.height / imgSize.height)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let drawX = targetRect.minX + (targetRect.width - drawW) / 2.0
        let drawY = targetRect.minY + (targetRect.height - drawH) / 2.0
        let finalRect = NSRect(x: drawX, y: drawY, width: drawW, height: drawH)

        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 30,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.58)
        )
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: finalRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    private static func drawCenteredText(_ text: String, attrs: [NSAttributedString.Key: Any], centerX: CGFloat, y: CGFloat) {
        let ns = NSString(string: text)
        let sz = ns.size(withAttributes: attrs)
        ns.draw(at: NSPoint(x: centerX - sz.width / 2.0, y: y), withAttributes: attrs)
    }

    // MARK: - High-Detail App Icon Renderer

    static func renderHighDetailAppIcon(size: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = nsCtx
        let cg = nsCtx.cgContext

        let s = CGFloat(size)
        let pad = s * 0.08
        let bgRect = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
        let cornerRadius = (s - 2 * pad) * 0.228
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // 1. macOS Squircle Base with Deep Space Indigo -> Carbon Gradient
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        cg.saveGState()
        cg.addPath(bgPath)
        cg.clip()

        if let bgGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.16, green: 0.21, blue: 0.31, alpha: 1.0),
                CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawLinearGradient(
                bgGrad,
                start: CGPoint(x: s * 0.5, y: s - pad),
                end: CGPoint(x: s * 0.5, y: pad),
                options: []
            )
        }

        // Subtle top-left cyan ambient rim glow inside squircle
        if let ambient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.16, green: 0.64, blue: 0.98, alpha: 0.24),
                CGColor(red: 0.16, green: 0.64, blue: 0.98, alpha: 0.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawRadialGradient(
                ambient,
                startCenter: CGPoint(x: s * 0.28, y: s * 0.82),
                startRadius: 0,
                endCenter: CGPoint(x: s * 0.28, y: s * 0.82),
                endRadius: s * 0.55,
                options: []
            )
        }
        cg.restoreGState()

        cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        cg.setLineWidth(max(1.0, s * 0.011))
        cg.addPath(bgPath)
        cg.strokePath()

        // 2. Machined Aluminum Monitor Mount / Base
        let baseRect = CGRect(x: s * 0.27, y: s * 0.155, width: s * 0.46, height: s * 0.068)
        let basePath = CGPath(roundedRect: baseRect, cornerWidth: s * 0.034, cornerHeight: s * 0.034, transform: nil)
        cg.saveGState()
        cg.addPath(basePath)
        cg.clip()
        if let baseGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.78, green: 0.83, blue: 0.90, alpha: 1.0),
                CGColor(red: 0.48, green: 0.54, blue: 0.63, alpha: 1.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawLinearGradient(
                baseGrad,
                start: CGPoint(x: s * 0.5, y: baseRect.maxY),
                end: CGPoint(x: s * 0.5, y: baseRect.minY),
                options: []
            )
        }
        cg.restoreGState()

        let neckRect = CGRect(x: s * 0.435, y: s * 0.21, width: s * 0.13, height: s * 0.11)
        cg.setFillColor(CGColor(red: 0.42, green: 0.47, blue: 0.56, alpha: 1.0))
        cg.fill(neckRect)

        // 3. Brushed Silver Outer Webcam Housing
        let lensCenter = CGPoint(x: s * 0.5, y: s * 0.565)
        let outerRadius = s * 0.278
        let outerRect = CGRect(
            x: lensCenter.x - outerRadius,
            y: lensCenter.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.045, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        cg.setFillColor(CGColor(red: 0.85, green: 0.89, blue: 0.94, alpha: 1.0))
        cg.fillEllipse(in: outerRect)
        cg.restoreGState()

        cg.saveGState()
        cg.addEllipse(in: outerRect)
        cg.clip()
        if let bodyGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.95, green: 0.97, blue: 0.99, alpha: 1.0),
                CGColor(red: 0.64, green: 0.70, blue: 0.79, alpha: 1.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        ) {
            cg.drawLinearGradient(
                bodyGrad,
                start: CGPoint(x: lensCenter.x, y: lensCenter.y + outerRadius),
                end: CGPoint(x: lensCenter.x, y: lensCenter.y - outerRadius),
                options: []
            )
        }
        cg.restoreGState()

        // 4. Anodized Dark Optical Barrel + Precision Ring
        let barrelRadius = s * 0.192
        let barrelRect = CGRect(
            x: lensCenter.x - barrelRadius,
            y: lensCenter.y - barrelRadius,
            width: barrelRadius * 2,
            height: barrelRadius * 2
        )
        cg.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1.0))
        cg.fillEllipse(in: barrelRect)

        let ringRadius = s * 0.162
        cg.setStrokeColor(CGColor(red: 0.25, green: 0.58, blue: 0.92, alpha: 0.55))
        cg.setLineWidth(max(1.0, s * 0.008))
        cg.strokeEllipse(in: CGRect(
            x: lensCenter.x - ringRadius,
            y: lensCenter.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))

        // 5. Multi-Coated Sapphire Optical Element
        let glassRadius = s * 0.132
        let glassRect = CGRect(
            x: lensCenter.x - glassRadius,
            y: lensCenter.y - glassRadius,
            width: glassRadius * 2,
            height: glassRadius * 2
        )
        cg.saveGState()
        cg.addEllipse(in: glassRect)
        cg.clip()
        if let glassGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.22, green: 0.72, blue: 1.00, alpha: 1.0),
                CGColor(red: 0.07, green: 0.28, blue: 0.66, alpha: 1.0),
                CGColor(red: 0.03, green: 0.10, blue: 0.26, alpha: 1.0)
            ] as CFArray,
            locations: [0.0, 0.58, 1.0]
        ) {
            cg.drawRadialGradient(
                glassGrad,
                startCenter: CGPoint(x: lensCenter.x - glassRadius * 0.28, y: lensCenter.y + glassRadius * 0.30),
                startRadius: 0,
                endCenter: lensCenter,
                endRadius: glassRadius * 1.12,
                options: []
            )
        }
        cg.restoreGState()

        // Inner pupil + dual optical specular glints
        let pupilRadius = s * 0.052
        cg.setFillColor(CGColor(red: 0.02, green: 0.05, blue: 0.13, alpha: 0.72))
        cg.fillEllipse(in: CGRect(
            x: lensCenter.x - pupilRadius,
            y: lensCenter.y - pupilRadius,
            width: pupilRadius * 2,
            height: pupilRadius * 2
        ))

        let glintRadius = s * 0.034
        cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.82))
        cg.fillEllipse(in: CGRect(
            x: lensCenter.x - glassRadius * 0.50,
            y: lensCenter.y + glassRadius * 0.20,
            width: glintRadius * 2,
            height: glintRadius * 2
        ))

        let secondaryGlint = s * 0.015
        cg.setFillColor(CGColor(red: 0.55, green: 0.88, blue: 1.0, alpha: 0.60))
        cg.fillEllipse(in: CGRect(
            x: lensCenter.x + glassRadius * 0.24,
            y: lensCenter.y - glassRadius * 0.42,
            width: secondaryGlint * 2,
            height: secondaryGlint * 2
        ))

        // Glowing Emerald Hardware-Active Indicator LED
        let ledRadius = s * 0.019
        let ledCenter = CGPoint(x: lensCenter.x, y: lensCenter.y + outerRadius * 0.77)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: s * 0.02, color: CGColor(red: 0.16, green: 0.92, blue: 0.48, alpha: 0.9))
        cg.setFillColor(CGColor(red: 0.18, green: 0.90, blue: 0.47, alpha: 1.0))
        cg.fillEllipse(in: CGRect(
            x: ledCenter.x - ledRadius,
            y: ledCenter.y - ledRadius,
            width: ledRadius * 2,
            height: ledRadius * 2
        ))
        cg.restoreGState()

        return rep
    }
}

// MARK: - Menu Bar Strip + Popover Showcase Wrapper

private struct MenuBarShowcaseCardView: View {
    @ObservedObject var manager: CameraManager

    var body: some View {
        VStack(spacing: 8) {
            // Simulated macOS Top Menu Bar Strip
            HStack(spacing: 14) {
                Text("")
                    .font(.system(size: 13, weight: .semibold))
                Text("Zoom")
                    .font(.system(size: 12, weight: .bold))
                Text("Video")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()

                // Highlighted WebCam Controller Menu Bar Icon Pill
                HStack(spacing: 4) {
                    Image(systemName: "web.camera.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accentColor)
                )

                Image(systemName: "wifi")
                    .font(.system(size: 11.5))
                Text("10:42")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )

            // Actual MenuBarPopoverView
            MenuBarPopoverView(manager: manager) { _ in }
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.16), lineWidth: 1)
                )

            Spacer(minLength: 0)
        }
        .padding(8)
    }
}
