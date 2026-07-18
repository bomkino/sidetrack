import AppKit
import CoreText

enum Palette {
    static let background = NSColor(calibratedRed: 0.052, green: 0.049, blue: 0.041, alpha: 1)
    static let warmInk = NSColor(calibratedRed: 0.078, green: 0.069, blue: 0.055, alpha: 1)
    static let paper = NSColor(calibratedRed: 0.84, green: 0.80, blue: 0.71, alpha: 1)
    static let quiet = NSColor(calibratedRed: 0.49, green: 0.45, blue: 0.38, alpha: 1)
    static let faint = NSColor(calibratedRed: 0.25, green: 0.23, blue: 0.19, alpha: 1)
    static let hairline = NSColor(calibratedRed: 0.19, green: 0.17, blue: 0.14, alpha: 1)
    static let ochre = NSColor(calibratedRed: 0.63, green: 0.47, blue: 0.25, alpha: 1)

    private static let grain = NSColor(patternImage: makeGrain())

    static func drawBackground(in rect: NSRect) {
        background.setFill()
        rect.fill()
        let glow = NSGradient(colorsAndLocations:
            (warmInk, 0),
            (background, 0.72)
        )
        glow?.draw(fromCenter: NSPoint(x: rect.width * 0.32, y: rect.height * 0.56), radius: 0,
                   toCenter: NSPoint(x: rect.width * 0.32, y: rect.height * 0.56), radius: rect.width * 0.72,
                   options: [])
        grain.setFill()
        rect.fill(using: .sourceOver)
    }

    private static func makeGrain() -> NSImage {
        let size = 96
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        )!
        var state: UInt64 = 0x5349444554524143
        for y in 0..<size {
            for x in 0..<size {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                let opacity = CGFloat((state >> 61) & 0x03) / 255
                rep.setColor(
                    NSColor(calibratedRed: 0.74, green: 0.65, blue: 0.49, alpha: opacity),
                    atX: x,
                    y: y
                )
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}

enum Typography {
    static func registerBundledFonts() {
        guard let resources = Bundle.main.resourceURL else { return }
        for name in ["Newsreader.ttf", "Newsreader-Italic.ttf"] {
            CTFontManagerRegisterFontsForURL(resources.appendingPathComponent(name) as CFURL, .process, nil)
        }
    }

    static func roman(_ size: CGFloat) -> NSFont {
        NSFont(name: "Newsreader16pt-Regular", size: size) ?? .systemFont(ofSize: size, weight: .regular)
    }

    static func italic(_ size: CGFloat) -> NSFont {
        NSFont(name: "Newsreader16pt-Italic", size: size) ?? .systemFont(ofSize: size, weight: .light)
    }
}

func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    tracking: CGFloat = 0,
    lineHeight: CGFloat = 1,
    strike: Bool = false
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = lineHeight

    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking
    ]
    if strike {
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        attributes[.strikethroughColor] = Palette.quiet
    }
    (text as NSString).draw(
        with: rect,
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
        attributes: attributes
    )
}

func drawCheck(in rect: NSRect, checked: Bool, prominent: Bool = false) {
    let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
    (prominent ? Palette.quiet : Palette.faint).setStroke()
    outline.lineWidth = 0.7
    outline.stroke()
    guard checked else { return }
    let tick = NSBezierPath()
    tick.move(to: NSPoint(x: rect.minX + 3, y: rect.midY + 0.5))
    tick.line(to: NSPoint(x: rect.minX + 6.5, y: rect.maxY - 3.5))
    tick.line(to: NSPoint(x: rect.maxX - 2.5, y: rect.minY + 3))
    Palette.ochre.setStroke()
    tick.lineWidth = 1.25
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    tick.stroke()
}
