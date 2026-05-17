import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("packaging/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let outputs: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

for output in outputs {
    let pixels = Int(output.points * output.scale)
    let image = drawIcon(size: CGFloat(pixels))
    let destination = iconsetURL.appendingPathComponent(output.name)
    try writePNG(image, to: destination)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.23
    let outerPath = CGPath(
        roundedRect: rect.insetBy(dx: size * 0.035, dy: size * 0.035),
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    context.saveGState()
    context.addPath(outerPath)
    context.clip()

    let colors = [
        cgColor(red: 17, green: 24, blue: 39),
        cgColor(red: 29, green: 78, blue: 216),
        cgColor(red: 6, green: 182, blue: 212)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.54, 1.0]
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: locations
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: size * 0.18, y: size * 0.94),
        end: CGPoint(x: size * 0.88, y: size * 0.08),
        options: []
    )

    drawGlow(context, size: size)
    drawGrid(context, size: size)
    context.restoreGState()

    drawOuterStroke(context, path: outerPath, size: size)
    drawTerminalCard(context, size: size)
    drawBell(context, size: size)

    image.unlockFocus()
    return image
}

func drawGlow(_ context: CGContext, size: CGFloat) {
    context.saveGState()
    context.setBlendMode(.screen)

    let glowRect = CGRect(
        x: size * 0.08,
        y: size * 0.50,
        width: size * 0.58,
        height: size * 0.42
    )
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            cgColor(red: 224, green: 242, blue: 254, alpha: 0.72),
            cgColor(red: 224, green: 242, blue: 254, alpha: 0.0)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
        startRadius: size * 0.02,
        endCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
        endRadius: size * 0.38,
        options: []
    )

    context.restoreGState()
}

func drawGrid(_ context: CGContext, size: CGFloat) {
    context.saveGState()
    context.setStrokeColor(cgColor(red: 255, green: 255, blue: 255, alpha: 0.08))
    context.setLineWidth(max(1, size * 0.004))

    for index in 0...5 {
        let offset = size * (0.18 + CGFloat(index) * 0.13)
        context.move(to: CGPoint(x: offset, y: size * 0.12))
        context.addLine(to: CGPoint(x: offset + size * 0.34, y: size * 0.88))
        context.strokePath()
    }

    context.restoreGState()
}

func drawOuterStroke(_ context: CGContext, path: CGPath, size: CGFloat) {
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(cgColor(red: 255, green: 255, blue: 255, alpha: 0.22))
    context.setLineWidth(max(1, size * 0.015))
    context.strokePath()
    context.restoreGState()
}

func drawTerminalCard(_ context: CGContext, size: CGFloat) {
    let card = CGRect(
        x: size * 0.19,
        y: size * 0.22,
        width: size * 0.62,
        height: size * 0.52
    )
    let path = CGPath(
        roundedRect: card,
        cornerWidth: size * 0.10,
        cornerHeight: size * 0.10,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.025),
        blur: size * 0.06,
        color: cgColor(red: 2, green: 6, blue: 23, alpha: 0.32)
    )
    context.addPath(path)
    context.setFillColor(cgColor(red: 15, green: 23, blue: 42, alpha: 0.48))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(cgColor(red: 255, green: 255, blue: 255, alpha: 0.16))
    context.setLineWidth(max(1, size * 0.010))
    context.strokePath()
    context.restoreGState()

    drawCodeChevron(context, size: size)
}

func drawCodeChevron(_ context: CGContext, size: CGFloat) {
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(cgColor(red: 125, green: 211, blue: 252, alpha: 0.76))
    context.setLineWidth(max(2, size * 0.045))

    context.move(to: CGPoint(x: size * 0.32, y: size * 0.48))
    context.addLine(to: CGPoint(x: size * 0.41, y: size * 0.56))
    context.addLine(to: CGPoint(x: size * 0.32, y: size * 0.64))
    context.strokePath()

    context.move(to: CGPoint(x: size * 0.50, y: size * 0.40))
    context.addLine(to: CGPoint(x: size * 0.60, y: size * 0.68))
    context.strokePath()

    context.restoreGState()
}

func drawBell(_ context: CGContext, size: CGFloat) {
    let bell = CGMutablePath()
    bell.move(to: CGPoint(x: size * 0.36, y: size * 0.39))
    bell.addCurve(
        to: CGPoint(x: size * 0.40, y: size * 0.64),
        control1: CGPoint(x: size * 0.36, y: size * 0.50),
        control2: CGPoint(x: size * 0.38, y: size * 0.59)
    )
    bell.addCurve(
        to: CGPoint(x: size * 0.60, y: size * 0.64),
        control1: CGPoint(x: size * 0.45, y: size * 0.72),
        control2: CGPoint(x: size * 0.55, y: size * 0.72)
    )
    bell.addCurve(
        to: CGPoint(x: size * 0.64, y: size * 0.39),
        control1: CGPoint(x: size * 0.62, y: size * 0.59),
        control2: CGPoint(x: size * 0.64, y: size * 0.50)
    )
    bell.addCurve(
        to: CGPoint(x: size * 0.70, y: size * 0.32),
        control1: CGPoint(x: size * 0.64, y: size * 0.35),
        control2: CGPoint(x: size * 0.66, y: size * 0.33)
    )
    bell.addLine(to: CGPoint(x: size * 0.30, y: size * 0.32))
    bell.addCurve(
        to: CGPoint(x: size * 0.36, y: size * 0.39),
        control1: CGPoint(x: size * 0.34, y: size * 0.33),
        control2: CGPoint(x: size * 0.36, y: size * 0.35)
    )
    bell.closeSubpath()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: size * 0.035,
        color: cgColor(red: 2, green: 6, blue: 23, alpha: 0.36)
    )
    context.addPath(bell)
    context.setFillColor(cgColor(red: 248, green: 250, blue: 252, alpha: 0.95))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.setFillColor(cgColor(red: 248, green: 250, blue: 252, alpha: 0.95))
    context.fillEllipse(in: CGRect(x: size * 0.465, y: size * 0.665, width: size * 0.07, height: size * 0.07))
    context.fillEllipse(in: CGRect(x: size * 0.455, y: size * 0.265, width: size * 0.09, height: size * 0.09))
    context.restoreGState()

    context.saveGState()
    context.setStrokeColor(cgColor(red: 14, green: 165, blue: 233, alpha: 0.70))
    context.setLineCap(.round)
    context.setLineWidth(max(2, size * 0.020))
    context.move(to: CGPoint(x: size * 0.50, y: size * 0.48))
    context.addLine(to: CGPoint(x: size * 0.59, y: size * 0.48))
    context.strokePath()
    context.restoreGState()
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw IconError.renderFailed
    }

    try pngData.write(to: url, options: [.atomic])
}

func cgColor(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat = 1
) -> CGColor {
    CGColor(
        red: red / 255,
        green: green / 255,
        blue: blue / 255,
        alpha: alpha
    )
}

enum IconError: Error {
    case renderFailed
}
