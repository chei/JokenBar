import AppKit
import CoreText

/// The fixed "JB" menu bar icon. Only the enclosed areas of the B change color
/// with the usage level, so the shape never moves.
enum StatusIcon {
    private static let font: CTFont = {
        let base = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let serif = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return (NSFont(descriptor: serif, size: 15) ?? base) as CTFont
    }()

    private static let baseline: CGFloat = 4.5
    private static let letterJ = glyph("J", x: 1)
    private static let letterB = glyph("B", x: 1 + glyph("J", x: 0).boundingBoxOfPath.maxX + 0.3)
    /// The B with its counters filled: every contour filled on its own.
    private static let silhouetteB = contours(of: letterB)
    private static let size = NSSize(width: ceil(letterB.boundingBoxOfPath.maxX + 1), height: 18)

    /// Drawn on demand, so the label color follows the menu bar's light or dark appearance.
    static func image(level: NSColor?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if let level {
                context.setFillColor(level.cgColor)
                for contour in silhouetteB {
                    context.addPath(contour)
                    context.fillPath()
                }
            }
            context.addPath(letterJ)
            context.addPath(letterB)
            context.setFillColor(NSColor.labelColor.cgColor)
            context.fillPath()
            return true
        }
        // Without a level there is nothing colored, so let AppKit tint it like other menu bar icons.
        image.isTemplate = level == nil
        image.accessibilityDescription = "Claude usage"
        return image
    }

    private static func glyph(_ letter: String, x: CGFloat) -> CGPath {
        let path = CGMutablePath()
        var characters = Array(letter.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        if let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) {
            path.addPath(outline, transform: CGAffineTransform(translationX: x, y: baseline))
        }
        return path
    }

    private static func contours(of path: CGPath) -> [CGPath] {
        var result: [CGPath] = []
        var current = CGMutablePath()
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                if !current.isEmpty { result.append(current) }
                current = CGMutablePath()
                current.move(to: points[0])
            case .addLineToPoint: current.addLine(to: points[0])
            case .addQuadCurveToPoint: current.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: current.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath: current.closeSubpath()
            @unknown default: break
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
