import PDFKit
import UIKit
import XCTest
@testable import Margin

final class TemplateScannerTests: XCTestCase {
    func testHomographyMapsCornersAndCentre() throws {
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100)]
        let target = [CGPoint(x: 10, y: 20), CGPoint(x: 210, y: 25), CGPoint(x: 5, y: 220), CGPoint(x: 215, y: 230)]
        let mapping = try XCTUnwrap(Homography.fit(from: source, to: target))
        for (s, t) in zip(source, target) {
            let mapped = mapping.map(s)
            XCTAssertEqual(mapped.x, t.x, accuracy: 0.001)
            XCTAssertEqual(mapped.y, t.y, accuracy: 0.001)
        }
        XCTAssertNil(Homography.fit(from: Array(source.prefix(3)), to: Array(target.prefix(3))))
    }

    func testTemplateCoversEveryCharacterAndPrints() throws {
        let page1 = Set(HandwritingTemplate.pages[0].boxes.map(\.item.text))
        XCTAssertTrue(Set(HandwritingCharset.all).isSubset(of: page1))
        XCTAssertTrue(HandwritingTemplate.pages[1].boxes.contains { $0.isWide })
        for page in HandwritingTemplate.pages {
            for box in page.boxes {
                XCTAssertGreaterThan(box.rect.minY, 30, "box \(box.item.text) collides with the header")
                XCTAssertLessThan(box.rect.maxY, 270, "box \(box.item.text) reaches the bottom markers")
            }
        }
        let document = try XCTUnwrap(PDFDocument(data: HandwritingTemplate.pdf()))
        XCTAssertEqual(document.pageCount, HandwritingTemplate.pages.count)
    }

    func testInkMaskIgnoresLightGuideAndBridgesDarkLine() throws {
        // 20 × 20 box: paper 240, a light guide row (210), a dark printed line (90)
        // crossed by a vertical pen stroke (40).
        let size = 20
        var pixels = [UInt8](repeating: 240, count: size * size)
        for x in 0..<size {
            pixels[5 * size + x] = 210
            pixels[12 * size + x] = 90
        }
        for y in 2..<18 { pixels[y * size + 10] = 40 }
        let mask = try XCTUnwrap(TemplateScanner.inkMask(pixels, width: size, height: size))
        XCTAssertEqual(mask[5 * size + 3], 255, "light guide counted as ink")
        XCTAssertEqual(mask[12 * size + 3], 255, "printed line not removed")
        XCTAssertEqual(mask[12 * size + 10], 0, "pen stroke crossing the line was cut")
        XCTAssertEqual(mask[8 * size + 10], 0)
        XCTAssertNil(TemplateScanner.inkMask([UInt8](repeating: 240, count: size * size), width: size, height: size))
    }

    /// Prints page 1 at 8 px/mm, "writes" an o and an l with a pen, tilts the
    /// photo by 2° and checks that both come back at the right size.
    func testScansAFilledInTiltedTemplate() throws {
        let page = HandwritingTemplate.pages[0]
        let pxPerMM: CGFloat = 8
        let canvas = CGSize(width: 226 * pxPerMM, height: 313 * pxPerMM)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: 0.93, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: canvas))
            cg.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            cg.rotate(by: 2 * .pi / 180)
            cg.scaleBy(x: pxPerMM, y: pxPerMM)
            cg.translateBy(x: -105, y: -148.5)
            HandwritingTemplate.draw(page, in: cg)

            cg.setStrokeColor(UIColor(red: 0.1, green: 0.15, blue: 0.5, alpha: 1).cgColor)
            cg.setLineWidth(0.5)
            if let o = page.boxes.first(where: { $0.item == .character("o") }) {
                let guide = HandwritingTemplate.guide(for: o)
                cg.strokeEllipse(in: CGRect(x: o.rect.midX - guide.xHeight / 2, y: guide.baseline - guide.xHeight,
                                            width: guide.xHeight, height: guide.xHeight))
            }
            if let l = page.boxes.first(where: { $0.item == .character("l") }) {
                let guide = HandwritingTemplate.guide(for: l)
                cg.move(to: CGPoint(x: l.rect.midX, y: guide.baseline - guide.xHeight * 1.8))
                cg.addLine(to: CGPoint(x: l.rect.midX, y: guide.baseline))
                cg.strokePath()
            }
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let result = try TemplateScanner.scan(cgImage)

        XCTAssertEqual(result.page, 1)
        XCTAssertEqual(Set(result.glyphs.map(\.item.text)), ["o", "l"])
        XCTAssertEqual(result.emptyBoxes, page.boxes.count - 2)

        let o = try XCTUnwrap(result.glyphs.first { $0.item == .character("o") })
        let oBounds = try XCTUnwrap(GlyphBounds(o.outlines))
        XCTAssertEqual(oBounds.minY, -1.06, accuracy: 0.12)
        XCTAssertEqual(oBounds.maxY, 0.06, accuracy: 0.12)
        XCTAssertEqual(oBounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(o.outlines.count, 2, "an o is an outer ring plus a hole")
        let areas = o.outlines.map { polygon in
            StrokeOutline.signedArea(polygon.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        }
        XCTAssertTrue(areas.contains { $0 < 0 } && areas.contains { $0 > 0 }, "ring and hole need opposite orientation")

        let l = try XCTUnwrap(result.glyphs.first { $0.item == .character("l") })
        let lBounds = try XCTUnwrap(GlyphBounds(l.outlines))
        XCTAssertEqual(lBounds.minY, -1.86, accuracy: 0.15)
        XCTAssertEqual(lBounds.maxY, 0.06, accuracy: 0.15)

        // The traced glyphs render like any other handwriting.
        var source = FontSource()
        source.glyphs["o"] = [GlyphInput(uid: UUID(), strokes: [], scale: 1, baselineOffset: 0, outlines: o.outlines)]
        let font = HandwritingFont(source: source, penRatio: 0.15)
        XCTAssertNotNil(font.variants(for: "o")?.first)
    }

    func testOutlineDataRoundTrip() {
        let polygon: Stroke = [StrokePoint(x: 0, y: 0, w: 0), StrokePoint(x: 1, y: 0, w: 0), StrokePoint(x: 0.5, y: -1, w: 0)]
        let data = GlyphStrokes.encodeOutlines([polygon])
        let decoded = GlyphStrokes.decodeGlyph(data)
        XCTAssertEqual(decoded.outlines, [polygon])
        XCTAssertTrue(decoded.strokes.isEmpty)
        XCTAssertTrue(GlyphStrokes.decode(data).isEmpty, "outline data must not be read as finger strokes")
    }
}
