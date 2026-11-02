import CoreGraphics
import UIKit

/// A printable A4 sheet with one box per character, filled in with a real pen
/// and scanned back in. All geometry is in millimetres from the top-left corner.
///
/// Four black corner markers let the scanner straighten skewed or tilted
/// photos; small squares at the top encode the page number. Guide lines and
/// box borders are printed light grey so they can be told apart from pen ink.
enum HandwritingTemplate {
    struct Box: Identifiable {
        var id: String { item.id + "-\(index)" }
        let item: CaptureItem
        /// Position on the page, so the same character can appear more than once.
        let index: Int
        let rect: CGRect
        var isWide: Bool { rect.width > HandwritingTemplate.boxSize.width * 2 }
    }

    struct Page {
        let number: Int
        let boxes: [Box]
    }

    static let pageSize = CGSize(width: 210, height: 297)
    static let boxSize = CGSize(width: 15, height: 20)
    static let columns = 11
    static let gap: CGFloat = 1.5
    static let rowPitch: CGFloat = 25
    static let gridOrigin = CGPoint(x: 15, y: 38)
    static let markerSize: CGFloat = 7
    /// Marker centres: top-left, top-right, bottom-left, bottom-right.
    static let markerCenters = [
        CGPoint(x: 12, y: 12), CGPoint(x: 198, y: 12),
        CGPoint(x: 12, y: 285), CGPoint(x: 198, y: 285),
    ]
    static let pageIDSquareSize: CGFloat = 4
    static let pageIDCenters = [CGPoint(x: 99, y: 11), CGPoint(x: 107, y: 11)]

    /// Box inset kept clear of the printed border when reading ink.
    static let readInset: CGFloat = 0.8

    static let pages: [Page] = {
        let extras = "entsradhuli".map { CaptureItem.character(String($0)) }
        let first = HandwritingCharset.all.map { CaptureItem.character($0) } + extras
        let second = HandwritingCharset.lowercase.flatMap { [CaptureItem.character($0), .character($0)] }
        return [
            Page(number: 1, boxes: layout(first, wide: nil)),
            Page(number: 2, boxes: layout(second, wide: .sampleWord(HandwritingCharset.sampleWord))),
        ]
    }()

    private static func layout(_ items: [CaptureItem], wide: CaptureItem?) -> [Box] {
        let capacity = columns * 9
        var boxes: [Box] = []
        for (index, item) in items.prefix(capacity).enumerated() {
            let row = index / columns, column = index % columns
            let origin = CGPoint(x: gridOrigin.x + CGFloat(column) * (boxSize.width + gap),
                                 y: gridOrigin.y + CGFloat(row) * rowPitch)
            boxes.append(Box(item: item, index: index, rect: CGRect(origin: origin, size: boxSize)))
        }
        if let wide {
            let row = (min(items.count, capacity) + columns - 1) / columns
            let width = CGFloat(columns) * boxSize.width + CGFloat(columns - 1) * gap
            let rect = CGRect(x: gridOrigin.x, y: gridOrigin.y + CGFloat(row) * rowPitch, width: width, height: boxSize.height)
            boxes.append(Box(item: wide, index: boxes.count, rect: rect))
        }
        return boxes
    }

    /// Guide lines inside a box (same proportions as the finger capture box).
    static func guide(for box: Box) -> (baseline: CGFloat, xHeight: CGFloat) {
        let guide = CaptureGuide(size: box.rect.size)
        return (box.rect.minY + guide.baseline, guide.xHeight)
    }

    // MARK: PDF

    static func pdf() -> Data {
        let scale = 72 / 25.4 as CGFloat
        let bounds = CGRect(x: 0, y: 0, width: pageSize.width * scale, height: pageSize.height * scale)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Margin Handschrift-Vorlage"]
        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for page in pages {
                context.beginPage()
                context.cgContext.scaleBy(x: scale, y: scale)
                draw(page, in: context.cgContext)
            }
        }
    }

    /// Draws a page in millimetre coordinates (y pointing down).
    static func draw(_ page: Page, in context: CGContext) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: pageSize))

        context.setFillColor(UIColor.black.cgColor)
        for center in markerCenters {
            context.fill(CGRect(x: center.x - markerSize / 2, y: center.y - markerSize / 2, width: markerSize, height: markerSize))
        }
        for (index, center) in pageIDCenters.enumerated() {
            let rect = CGRect(x: center.x - pageIDSquareSize / 2, y: center.y - pageIDSquareSize / 2,
                              width: pageIDSquareSize, height: pageIDSquareSize)
            if index < page.number {
                context.fill(rect)
            } else {
                context.setStrokeColor(UIColor(white: 0.6, alpha: 1).cgColor)
                context.setLineWidth(0.2)
                context.stroke(rect)
            }
        }

        UIGraphicsPushContext(context)
        text("Margin · Handschrift-Vorlage · Seite \(page.number) von \(pages.count)", at: CGPoint(x: 105, y: 17),
             size: 4.2, gray: 0.3, centered: true, bold: true)
        let lines = page.number == 1
            ? ["Mit deinem normalen Stift schreiben (blau oder schwarz). Ein Zeichen pro Kästchen, auf der durchgezogenen Linie.",
               "Kleinbuchstaben bis zur gestrichelten Linie. Nicht über die Ränder schreiben, die schwarzen Ecken frei lassen."]
            : ["Hier schreibst du jeden Kleinbuchstaben noch zweimal – dann sieht Text weniger kopiert aus.",
               "Unten das Wort „Handschrift“ in einem Zug, so wie du normal schreibst (daraus wird der Abstand gemessen)."]
        for (index, line) in lines.enumerated() {
            text(line, at: CGPoint(x: 105, y: 24 + CGFloat(index) * 4), size: 2.9, gray: 0.4, centered: true)
        }

        for box in page.boxes {
            let label = box.isWide ? "„\(box.item.text)“ – in einem Zug" : box.item.text
            text(label, at: CGPoint(x: box.rect.minX + 0.6, y: box.rect.minY - 3.6), size: 2.8, gray: 0.45)
        }
        UIGraphicsPopContext()

        for box in page.boxes {
            let guide = CaptureGuide(size: box.rect.size)
            func line(_ y: CGFloat, gray: CGFloat, width: CGFloat, dash: [CGFloat]) {
                context.setStrokeColor(UIColor(white: gray, alpha: 1).cgColor)
                context.setLineWidth(width)
                context.setLineDash(phase: 0, lengths: dash)
                context.move(to: CGPoint(x: box.rect.minX + 0.6, y: box.rect.minY + y))
                context.addLine(to: CGPoint(x: box.rect.maxX - 0.6, y: box.rect.minY + y))
                context.strokePath()
            }
            line(guide.capLine, gray: 0.88, width: 0.15, dash: [0.6, 1.2])
            line(guide.xLine, gray: 0.82, width: 0.2, dash: [1.2, 1])
            line(guide.baseline, gray: 0.72, width: 0.3, dash: [])
            line(guide.descenderLine, gray: 0.88, width: 0.15, dash: [0.6, 1.2])
            context.setLineDash(phase: 0, lengths: [])
            context.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor)
            context.setLineWidth(0.25)
            context.stroke(box.rect)
        }
    }

    private static func text(_ string: String, at point: CGPoint, size: CGFloat, gray: CGFloat,
                             centered: Bool = false, bold: Bool = false) {
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: UIColor(white: gray, alpha: 1),
        ])
        let width = attributed.size().width
        attributed.draw(at: CGPoint(x: centered ? point.x - width / 2 : point.x, y: point.y))
    }
}
