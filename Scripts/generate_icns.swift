import AppKit
import CoreGraphics
import Foundation

func renderWebcamAppIcon(size: Int) -> NSBitmapImageRep? {
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

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    if let rep = renderWebcamAppIcon(size: px),
       let pngData = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
        try pngData.write(to: url)
    }
}
print("Generated iconset at \(outputDir)")
