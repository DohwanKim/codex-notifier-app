import AppKit
import CoreGraphics

enum MenuBarStatusIconState: Equatable {
    case normal
    case warning
    case failure

    static func make(hasFailures: Bool, hasMissingConfiguredChannel: Bool) -> MenuBarStatusIconState {
        if hasFailures {
            return .failure
        }

        if hasMissingConfiguredChannel {
            return .warning
        }

        return .normal
    }
}

@MainActor
enum MenuBarStatusIconImage {
    static func make(for state: MenuBarStatusIconState, pointSize: CGFloat = 22) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)

        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            draw(state: state, in: context, pointSize: pointSize)
        }
        image.unlockFocus()

        image.isTemplate = true
        return image
    }

    private static func draw(state: MenuBarStatusIconState, in context: CGContext, pointSize: CGFloat) {
        context.clear(CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        context.saveGState()
        context.translateBy(x: 0, y: pointSize)
        context.scaleBy(x: pointSize / 24, y: -pointSize / 24)

        drawBell(in: context)
        cutPrompt(from: context)
        drawMarker(for: state, in: context)

        context.restoreGState()
    }

    private static func drawBell(in context: CGContext) {
        context.setFillColor(NSColor.black.cgColor)

        let bell = CGMutablePath()
        bell.move(to: CGPoint(x: 5.55, y: 17.85))
        bell.addLine(to: CGPoint(x: 18.45, y: 17.85))
        bell.addCurve(
            to: CGPoint(x: 17.05, y: 16.35),
            control1: CGPoint(x: 18.2, y: 17.2),
            control2: CGPoint(x: 17.65, y: 16.75)
        )
        bell.addCurve(
            to: CGPoint(x: 16.62, y: 14.78),
            control1: CGPoint(x: 16.78, y: 15.88),
            control2: CGPoint(x: 16.62, y: 15.35)
        )
        bell.addLine(to: CGPoint(x: 16.62, y: 10.58))
        bell.addCurve(
            to: CGPoint(x: 12, y: 5.92),
            control1: CGPoint(x: 16.62, y: 7.92),
            control2: CGPoint(x: 14.6, y: 5.92)
        )
        bell.addCurve(
            to: CGPoint(x: 7.38, y: 10.58),
            control1: CGPoint(x: 9.4, y: 5.92),
            control2: CGPoint(x: 7.38, y: 7.92)
        )
        bell.addLine(to: CGPoint(x: 7.38, y: 14.78))
        bell.addCurve(
            to: CGPoint(x: 6.95, y: 16.35),
            control1: CGPoint(x: 7.38, y: 15.35),
            control2: CGPoint(x: 7.22, y: 15.88)
        )
        bell.addCurve(
            to: CGPoint(x: 5.55, y: 17.85),
            control1: CGPoint(x: 6.35, y: 16.75),
            control2: CGPoint(x: 5.8, y: 17.2)
        )
        bell.closeSubpath()
        context.addPath(bell)
        context.fillPath()

        context.fillEllipse(in: CGRect(x: 10.95, y: 4.35, width: 2.1, height: 2.1))

        let clapper = CGPath(
            roundedRect: CGRect(x: 10.05, y: 18.7, width: 3.9, height: 1.55),
            cornerWidth: 0.78,
            cornerHeight: 0.78,
            transform: nil
        )
        context.addPath(clapper)
        context.fillPath()
    }

    private static func cutPrompt(from context: CGContext) {
        context.saveGState()
        context.setBlendMode(.clear)
        context.setStrokeColor(NSColor.clear.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(1.55)

        context.move(to: CGPoint(x: 8.65, y: 11.12))
        context.addLine(to: CGPoint(x: 10.75, y: 13))
        context.addLine(to: CGPoint(x: 8.65, y: 14.88))
        context.strokePath()

        context.move(to: CGPoint(x: 12.55, y: 14.78))
        context.addLine(to: CGPoint(x: 15.15, y: 14.78))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawMarker(for state: MenuBarStatusIconState, in context: CGContext) {
        switch state {
        case .normal:
            return
        case .warning:
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.45)
            context.strokeEllipse(in: CGRect(x: 16.05, y: 4.35, width: 4.7, height: 4.7))
        case .failure:
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: 15.82, y: 4.12, width: 5.16, height: 5.16))
            context.saveGState()
            context.setBlendMode(.clear)
            context.setStrokeColor(NSColor.clear.cgColor)
            context.setLineCap(.round)
            context.setLineWidth(0.9)
            context.move(to: CGPoint(x: 18.4, y: 5.25))
            context.addLine(to: CGPoint(x: 18.4, y: 6.85))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: 17.95, y: 7.45, width: 0.9, height: 0.9))
            context.restoreGState()
        }
    }
}
