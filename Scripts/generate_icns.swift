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
    let pad = s * 0.09
    let bgRect = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
    let cornerRadius = (s - 2 * pad) * 0.225

    // 1. macOS squircle background gradient (deep slate -> midnight blue)
    cg.saveGState()
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    cg.addPath(bgPath)
    cg.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.16, green: 0.19, blue: 0.26, alpha: 1.0),
        CGColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: s * 0.5, y: s - pad),
            end: CGPoint(x: s * 0.5, y: pad),
            options: []
        )
    }
    cg.restoreGState()

    // Subtle border
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
    cg.setLineWidth(max(1.0, s * 0.012))
    cg.addPath(bgPath)
    cg.strokePath()

    // 2. Webcam Stand / Clip Base
    let baseRect = CGRect(x: s * 0.29, y: s * 0.17, width: s * 0.42, height: s * 0.065)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: s * 0.03, cornerHeight: s * 0.03, transform: nil)
    cg.setFillColor(CGColor(red: 0.62, green: 0.67, blue: 0.76, alpha: 1.0))
    cg.addPath(basePath)
    cg.fillPath()

    let neckRect = CGRect(x: s * 0.44, y: s * 0.22, width: s * 0.12, height: s * 0.10)
    cg.setFillColor(CGColor(red: 0.46, green: 0.51, blue: 0.60, alpha: 1.0))
    cg.fill(neckRect)

    // 3. Outer Webcam Body Circle
    let lensCenter = CGPoint(x: s * 0.5, y: s * 0.56)
    let outerRadius = s * 0.27
    let outerRect = CGRect(
        x: lensCenter.x - outerRadius,
        y: lensCenter.y - outerRadius,
        width: outerRadius * 2,
        height: outerRadius * 2
    )
    cg.saveGState()
    cg.addEllipse(in: outerRect)
    cg.clip()
    let bodyColors = [
        CGColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1.0),
        CGColor(red: 0.68, green: 0.73, blue: 0.80, alpha: 1.0)
    ] as CFArray
    if let bodyGrad = CGGradient(colorsSpace: colorSpace, colors: bodyColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            bodyGrad,
            start: CGPoint(x: lensCenter.x, y: lensCenter.y + outerRadius),
            end: CGPoint(x: lensCenter.x, y: lensCenter.y - outerRadius),
            options: []
        )
    }
    cg.restoreGState()

    // 4. Dark Optical Barrel Ring
    let barrelRadius = s * 0.18
    let barrelRect = CGRect(
        x: lensCenter.x - barrelRadius,
        y: lensCenter.y - barrelRadius,
        width: barrelRadius * 2,
        height: barrelRadius * 2
    )
    cg.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1.0))
    cg.fillEllipse(in: barrelRect)

    // 5. Sapphire Optical Glass Element
    let glassRadius = s * 0.125
    let glassRect = CGRect(
        x: lensCenter.x - glassRadius,
        y: lensCenter.y - glassRadius,
        width: glassRadius * 2,
        height: glassRadius * 2
    )
    cg.saveGState()
    cg.addEllipse(in: glassRect)
    cg.clip()
    let glassColors = [
        CGColor(red: 0.18, green: 0.62, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.06, green: 0.22, blue: 0.52, alpha: 1.0)
    ] as CFArray
    if let glassGrad = CGGradient(colorsSpace: colorSpace, colors: glassColors, locations: [0.0, 1.0]) {
        cg.drawRadialGradient(
            glassGrad,
            startCenter: CGPoint(x: lensCenter.x - glassRadius * 0.3, y: lensCenter.y + glassRadius * 0.3),
            startRadius: 0,
            endCenter: lensCenter,
            endRadius: glassRadius * 1.15,
            options: []
        )
    }
    cg.restoreGState()

    // Specular lens glint + green status LED
    let glintRadius = s * 0.035
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
    cg.fillEllipse(in: CGRect(
        x: lensCenter.x - glassRadius * 0.48,
        y: lensCenter.y + glassRadius * 0.18,
        width: glintRadius * 2,
        height: glintRadius * 2
    ))

    let ledRadius = s * 0.018
    cg.setFillColor(CGColor(red: 0.18, green: 0.88, blue: 0.45, alpha: 1.0))
    cg.fillEllipse(in: CGRect(
        x: lensCenter.x - ledRadius,
        y: lensCenter.y + outerRadius * 0.76 - ledRadius,
        width: ledRadius * 2,
        height: ledRadius * 2
    ))

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
