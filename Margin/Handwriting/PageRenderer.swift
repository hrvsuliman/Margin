import CoreGraphics
import CoreText
import UIKit

/// Draws laid-out pages: paper, handwriting and fallback text. The same code
/// draws the on-screen pages, thumbnails and the exported PDF.
enum PageRenderer {
    static let paperColor = UIColor(hex: 0xFFFEFB)
    static let ruleColor = UIColor(hex: 0x9FBAD6)
    static let gridColor = UIColor(hex: 0xC3CDD8)
    static let marginColor = UIColor(hex: 0xE08A7E)

    /// Draws one page into a context whose origin is the page's top-left corner (y pointing down).
    static func draw(_ page: LaidOutPage?, settings: PageSettings, in context: CGContext, includePaper: Bool) {
        let size = settings.pageSize
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(paperColor.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        if includePaper {
            drawPaper(settings: settings, in: context)
        }

        guard let page else { return }
        let ink = UIColor(hex: settings.penColor.hex)
        context.setFillColor(ink.cgColor)
        context.addPath(page.ink)
        context.fillPath()

        if !page.fallbacks.isEmpty {
            UIGraphicsPushContext(context)
            for fallback in page.fallbacks {
                let font = UIFont(name: FallbackFont.name, size: fallback.fontSize)
                    ?? UIFont.italicSystemFont(ofSize: fallback.fontSize)
                let text = NSAttributedString(string: fallback.text, attributes: [
                    .font: font,
                    .foregroundColor: ink.withAlphaComponent(0.75),
                ])
                text.draw(at: CGPoint(x: fallback.origin.x, y: fallback.origin.y - font.ascender))
            }
            UIGraphicsPopContext()
        }
    }

    private static func drawPaper(settings: PageSettings, in context: CGContext) {
        let size = settings.pageSize
        switch settings.paper {
        case .lined:
            context.setStrokeColor(ruleColor.cgColor)
            context.setLineWidth(0.6)
            var y = settings.marginTop + settings.lineSpacing
            while y < size.height - PageSettings.mm(8) {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: size.width, y: y))
                y += settings.lineSpacing
            }
            context.strokePath()
        case .squared:
            let step = PageSettings.mm(5)
            context.setStrokeColor(gridColor.cgColor)
            context.setLineWidth(0.4)
            var y = settings.marginTop.truncatingRemainder(dividingBy: step)
            while y < size.height {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            var x = settings.marginLeft.truncatingRemainder(dividingBy: step)
            while x < size.width {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            context.strokePath()
        case .dotted:
            let step = PageSettings.mm(5)
            context.setFillColor(gridColor.cgColor)
            var y = settings.marginTop.truncatingRemainder(dividingBy: step)
            while y < size.height {
                var x = settings.marginLeft.truncatingRemainder(dividingBy: step)
                while x < size.width {
                    context.fillEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                    x += step
                }
                y += step
            }
        case .blank:
            break
        }

        if settings.showMarginLine && settings.paper != .blank {
            // German correction margin on the right.
            let x = size.width - settings.marginRight + PageSettings.mm(4)
            context.setStrokeColor(marginColor.cgColor)
            context.setLineWidth(0.7)
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: size.height))
            context.strokePath()
        }
    }

    /// A PDF with one A4 page per laid-out page.
    static func pdf(pages: [LaidOutPage], settings: PageSettings, title: String) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Margin",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: settings.pageSize), format: format)
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                draw(page, settings: settings, in: context.cgContext, includePaper: settings.printPaper)
            }
        }
    }

    /// A small picture of a page for the notes library.
    static func thumbnail(of page: LaidOutPage?, settings: PageSettings, width: CGFloat) -> UIImage {
        let scale = width / settings.pageSize.width
        let size = CGSize(width: width, height: settings.pageSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            draw(page, settings: settings, in: context.cgContext, includePaper: true)
        }
    }
}
