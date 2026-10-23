import AppKit
import CoreText

/// The fixed "JB" menu bar icon. The letters sit close together and the B's serifs
/// are extended back to the J, enclosing a slot between the stems; only that slot
/// changes color with the usage level.
enum StatusIcon {
    private static let font: CTFont = {
        let base = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let serif = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return (NSFont(descriptor: serif, size: 15) ?? base) as CTFont
    }()

    private static let baseline: CGFloat = 4.5
    private static let capHeight = CTFontGetCapHeight(font)
    /// The J's hook reaches left of its origin; shift it so the ink starts at the image edge.
    private static let originJ = -glyph("J", x: 0).boundingBoxOfPath.minX
    private static let letterJ = glyph("J", x: originJ)
    private static let originB = letterJ.boundingBoxOfPath.maxX - 0.75
    private static let letterB = glyph("B", x: originB)

    // Measured on the font's outlines: inner edges of the stems and the serif thickness.
    private static let stemJ = originJ + 3.85
    private static let stemB: CGFloat = originB + 1.7
    private static let serif: CGFloat = 0.65
    private static let bracket: CGFloat = 0.8

    /// Every edge of the slot lies under ink, so no color bleeds when antialiased.
    private static let slot = CGRect(x: stemJ - 0.5, y: baseline + 0.4,
                                     width: stemB - stemJ + 0.8, height: capHeight - 0.8)

    /// The extended serifs, plus a bracket rounding the slot's bottom-left corner
    /// the way the font's own brackets round the other three.
    private static let closure: CGPath = {
        let path = CGMutablePath()
        let left = stemJ - 0.5
        path.addRect(CGRect(x: left - 0.8, y: baseline, width: stemB + 0.3 - left + 0.8, height: serif))
        path.addRect(CGRect(x: left, y: baseline + capHeight - serif, width: stemB + 0.3 - left, height: serif))
        // The J's stem narrows towards its curve; keep the slot's left edge straight.
        path.addRect(CGRect(x: left, y: baseline, width: stemJ - left, height: capHeight / 2))
        path.move(to: CGPoint(x: left, y: baseline))
        path.addLine(to: CGPoint(x: stemJ + bracket, y: baseline))
        path.addLine(to: CGPoint(x: stemJ + bracket, y: baseline + serif))
        path.addArc(center: CGPoint(x: stemJ + bracket, y: baseline + serif + bracket), radius: bracket,
                    startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: left, y: baseline + serif + bracket))
        path.closeSubpath()
        return path
    }()

    private static let size = NSSize(width: ceil(letterB.boundingBoxOfPath.maxX), height: 18)

    /// Drawn on demand, so the label color follows the menu bar's light or dark appearance.
    static func image(level: NSColor?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if let level {
                context.setFillColor(level.cgColor)
                context.fill(slot)
            }
            context.setFillColor(NSColor.labelColor.cgColor)
            context.addPath(letterJ)
            context.addPath(letterB)
            context.fillPath()
            // Filled separately: where its contours overlap the glyphs' opposite
            // winding, a single fill would punch holes.
            context.addPath(closure)
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
}
