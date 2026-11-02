import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// An 8-bit greyscale copy of an image (0 = black, 255 = white), for fast pixel access.
struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage, maxDimension: Int = 2600) {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Bilinear sample; outside the image counts as white paper.
    func value(x: Double, y: Double) -> Double {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = fx - Double(x0), ty = fy - Double(y0)
        func at(_ px: Int, _ py: Int) -> Double {
            guard px >= 0, py >= 0, px < width, py < height else { return 255 }
            return Double(pixels[py * width + px])
        }
        let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
        let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
        return top * (1 - ty) + bottom * ty
    }

    /// The image as a CGImage (used for Vision).
    func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// A projective mapping between two planes, fitted from four point pairs.
/// Used to map template millimetres onto the photo, even when it is tilted.
struct Homography {
    private let h: [Double]

    static func fit(from source: [CGPoint], to target: [CGPoint]) -> Homography? {
        guard source.count == 4, target.count == 4 else { return nil }
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for index in 0..<4 {
            let u = Double(source[index].x), v = Double(source[index].y)
            let x = Double(target[index].x), y = Double(target[index].y)
            matrix[index * 2] = [u, v, 1, 0, 0, 0, -u * x, -v * x, x]
            matrix[index * 2 + 1] = [0, 0, 0, u, v, 1, -u * y, -v * y, y]
        }
        // Gaussian elimination with partial pivoting.
        for column in 0..<8 {
            guard let pivot = (column..<8).max(by: { abs(matrix[$0][column]) < abs(matrix[$1][column]) }),
                  abs(matrix[pivot][column]) > 1e-12 else { return nil }
            matrix.swapAt(column, pivot)
            for row in 0..<8 where row != column {
                let factor = matrix[row][column] / matrix[column][column]
                if factor == 0 { continue }
                for k in column..<9 {
                    matrix[row][k] -= factor * matrix[column][k]
                }
            }
        }
        return Homography(h: (0..<8).map { matrix[$0][8] / matrix[$0][$0] })
    }

    func map(_ point: CGPoint) -> CGPoint {
        let u = Double(point.x), v = Double(point.y)
        let w = h[6] * u + h[7] * v + 1
        return CGPoint(x: (h[0] * u + h[1] * v + h[2]) / w, y: (h[3] * u + h[4] * v + h[5]) / w)
    }
}

/// Reads a filled-in handwriting template: finds the page, cuts out every box,
/// keeps only the pen ink and traces it into outlines in x-height units.
enum TemplateScanner {
    struct Glyph: Identifiable {
        let id = UUID()
        let item: CaptureItem
        /// Closed outlines; baseline at y = 0, x-height at y = −1, ink starting at x = 0.
        let outlines: [Stroke]
    }

    struct PageResult {
        let page: Int
        let glyphs: [Glyph]
        let emptyBoxes: Int
    }

    enum ScanError: LocalizedError {
        case unreadable
        case markersNotFound

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "Das Bild konnte nicht gelesen werden."
            case .markersNotFound:
                "Die vier schwarzen Ecken der Vorlage wurden nicht gefunden. Fotografiere die ganze Seite, möglichst gerade und hell, ohne Schatten."
            }
        }
    }

    /// Pixels per millimetre used when cutting out a box.
    static let boxResolution: Double = 12

    // MARK: Page

    /// Straightens a photo of a sheet lying on a table (not needed for document-camera scans).
    static func straightenedPage(_ image: CGImage) -> CGImage {
        let request = VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let page = request.results?.first, page.confidence > 0.5 else { return image }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: p.y * height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = point(page.topLeft)
        filter.topRight = point(page.topRight)
        filter.bottomLeft = point(page.bottomLeft)
        filter.bottomRight = point(page.bottomRight)
        guard let output = filter.outputImage,
              let result = CIContext().createCGImage(output, from: output.extent) else { return image }
        return result
    }

    static func scan(_ image: CGImage, preferredPage: Int? = nil) throws -> PageResult {
        guard let gray = GrayImage(image) else { throw ScanError.unreadable }
        guard let markers = findMarkers(in: gray),
              let mapping = Homography.fit(from: HandwritingTemplate.markerCenters, to: markers) else {
            throw ScanError.markersNotFound
        }

        let pageNumber = detectPageNumber(gray, mapping: mapping) ?? preferredPage ?? 1
        let page = HandwritingTemplate.pages.first { $0.number == pageNumber } ?? HandwritingTemplate.pages[0]

        var glyphs: [Glyph] = []
        var empty = 0
        for box in page.boxes {
            if let outlines = readBox(box, gray: gray, mapping: mapping) {
                glyphs.append(Glyph(item: box.item, outlines: outlines))
            } else {
                empty += 1
            }
        }
        return PageResult(page: page.number, glyphs: glyphs, emptyBoxes: empty)
    }

    /// Centres of the four black corner squares, in image pixels (TL, TR, BL, BR).
    static func findMarkers(in gray: GrayImage) -> [CGPoint]? {
        let regionWidth = Int(Double(gray.width) * 0.14)
        let regionHeight = Int(Double(gray.height) * 0.1)
        let pixelsPerMM = Double(gray.width) / Double(HandwritingTemplate.pageSize.width)
        let expected = pow(Double(HandwritingTemplate.markerSize) * pixelsPerMM, 2)
        let corners = [
            (0, 0), (gray.width - regionWidth, 0),
            (0, gray.height - regionHeight), (gray.width - regionWidth, gray.height - regionHeight),
        ]

        var centers: [CGPoint] = []
        for (originX, originY) in corners {
            var values: [UInt8] = []
            values.reserveCapacity(regionWidth * regionHeight)
            for y in originY..<(originY + regionHeight) {
                for x in originX..<(originX + regionWidth) {
                    values.append(gray.pixels[y * gray.width + x])
                }
            }
            let paper = percentile(values, 0.9)
            let threshold = UInt8(Double(paper) * 0.45)
            var sumX = 0.0, sumY = 0.0, count = 0.0
            for y in originY..<(originY + regionHeight) {
                for x in originX..<(originX + regionWidth) where gray.pixels[y * gray.width + x] < threshold {
                    sumX += Double(x) + 0.5
                    sumY += Double(y) + 0.5
                    count += 1
                }
            }
            guard count > expected * 0.3, count < expected * 4 else { return nil }
            centers.append(CGPoint(x: sumX / count, y: sumY / count))
        }
        return centers
    }

    private static func detectPageNumber(_ gray: GrayImage, mapping: Homography) -> Int? {
        func average(around center: CGPoint, size: CGFloat) -> Double {
            var total = 0.0, count = 0.0
            for dy in stride(from: -size / 2, through: size / 2, by: size / 6) {
                for dx in stride(from: -size / 2, through: size / 2, by: size / 6) {
                    let p = mapping.map(CGPoint(x: center.x + dx, y: center.y + dy))
                    total += gray.value(x: Double(p.x), y: Double(p.y))
                    count += 1
                }
            }
            return total / max(count, 1)
        }
        let paper = average(around: CGPoint(x: 105, y: 5), size: 6)
        let filled = HandwritingTemplate.pageIDCenters.map {
            average(around: $0, size: HandwritingTemplate.pageIDSquareSize * 0.6) < paper * 0.55
        }
        let count = filled.prefix { $0 }.count
        return count > 0 ? count : nil
    }

    // MARK: Boxes

    /// Cuts out one box, keeps the pen ink and returns its outlines (nil if the box is empty).
    static func readBox(_ box: HandwritingTemplate.Box, gray: GrayImage, mapping: Homography) -> [Stroke]? {
        let inner = box.rect.insetBy(dx: HandwritingTemplate.readInset, dy: HandwritingTemplate.readInset)
        let resolution = boxResolution
        let width = Int(Double(inner.width) * resolution)
        let height = Int(Double(inner.height) * resolution)
        guard width > 4, height > 4 else { return nil }

        var samples = [UInt8](repeating: 255, count: width * height)
        for j in 0..<height {
            for i in 0..<width {
                let mm = CGPoint(x: inner.minX + CGFloat((Double(i) + 0.5) / resolution),
                                 y: inner.minY + CGFloat((Double(j) + 0.5) / resolution))
                let p = mapping.map(mm)
                samples[j * width + i] = UInt8(max(0, min(255, gray.value(x: Double(p.x), y: Double(p.y)))))
            }
        }

        guard let binary = inkMask(samples, width: width, height: height) else { return nil }
        let contours = traceContours(binary, width: width, height: height)
        guard !contours.isEmpty else { return nil }

        // Millimetres inside the box → x-height units around the box's baseline.
        let guide = HandwritingTemplate.guide(for: box)
        let unit = Double(guide.xHeight)
        var outlines: [Stroke] = contours.map { polygon -> Stroke in
            polygon.map { point -> StrokePoint in
                let xMM = Double(inner.minX) + Double(point.x) / resolution
                let yMM = Double(inner.minY) + Double(point.y) / resolution
                return StrokePoint(x: Float(xMM / unit), y: Float((yMM - Double(guide.baseline)) / unit), w: 0)
            }
        }
        guard let bounds = GlyphBounds(outlines) else { return nil }
        outlines = outlines.map { polygon in
            polygon.map { StrokePoint(x: $0.x - Float(bounds.minX), y: $0.y, w: 0) }
        }
        return outlines
    }

    /// Ink = clearly darker than this box's paper. Printed guide lines are light
    /// grey and stay out; any long straight line that still gets through (a dark
    /// print, a box border) is removed, bridging pen strokes that crossed it.
    /// Returns nil when there is (almost) no ink.
    static func inkMask(_ samples: [UInt8], width: Int, height: Int) -> [UInt8]? {
        let paper = Double(percentile(samples, 0.9))
        guard paper > 70 else { return nil }
        let threshold = UInt8(paper * 0.62)
        let original = samples.map { $0 < threshold }
        var ink = original

        // Horizontal lines: rows inked across most of the width. A pen stroke
        // crossing such a line is kept by bridging from the rows above and below.
        let lineRows = Set((0..<height).filter { y in
            Double((0..<width).filter { original[y * width + $0] }.count) > Double(width) * 0.85
        })
        for y in lineRows {
            var up = y - 1
            while up >= 0 && lineRows.contains(up) { up -= 1 }
            var down = y + 1
            while down < height && lineRows.contains(down) { down += 1 }
            for x in 0..<width {
                ink[y * width + x] = up >= 0 && down < height && original[up * width + x] && original[down * width + x]
            }
        }

        // Vertical lines (box borders after a slight misalignment).
        let afterRows = ink
        let lineColumns = Set((0..<width).filter { x in
            Double((0..<height).filter { afterRows[$0 * width + x] }.count) > Double(height) * 0.92
        })
        for x in lineColumns {
            var left = x - 1
            while left >= 0 && lineColumns.contains(left) { left -= 1 }
            var right = x + 1
            while right < width && lineColumns.contains(right) { right += 1 }
            for y in 0..<height {
                ink[y * width + x] = left >= 0 && right < width && afterRows[y * width + left] && afterRows[y * width + right]
            }
        }

        guard ink.filter({ $0 }).count >= 20 else { return nil }
        return ink.map { $0 ? 0 : 255 }
    }

    /// Outlines of the ink regions in pixel coordinates (y pointing down).
    /// Outer shapes get negative signed area, holes positive, matching the stroke outlines.
    static func traceContours(_ mask: [UInt8], width: Int, height: Int) -> [[CGPoint]] {
        guard let image = GrayImage(width: width, height: height, pixels: mask).cgImage() else { return [] }
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        request.contrastAdjustment = 1
        request.maximumImageDimension = max(width, height)
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return []
        }
        guard let observation = request.results?.first else { return [] }

        let minimumArea = CGFloat(pow(boxResolution * 0.3, 2)) // ~0.09 mm²
        var polygons: [[CGPoint]] = []

        func visit(_ contour: VNContour, depth: Int) {
            var points = contour.normalizedPoints.map {
                CGPoint(x: CGFloat($0.x) * CGFloat(width), y: (1 - CGFloat($0.y)) * CGFloat(height))
            }
            guard points.count > 2 else { return }
            let area = StrokeOutline.signedArea(points)
            guard abs(area) >= minimumArea else { return }
            if isStraightLine(points, width: width, height: height) && depth == 0 { return }
            let wantsNegative = depth % 2 == 0
            if (area < 0) != wantsNegative { points.reverse() }
            polygons.append(simplifyClosed(points, tolerance: boxResolution * 0.06))
            for child in contour.childContours {
                visit(child, depth: depth + 1)
            }
        }
        for contour in observation.topLevelContours {
            visit(contour, depth: 0)
        }
        return polygons
    }

    /// Thin shapes spanning most of the box are leftovers of printed lines.
    private static func isStraightLine(_ points: [CGPoint], width: Int, height: Int) -> Bool {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return false }
        let thin = CGFloat(boxResolution * 0.5)
        return (maxY - minY < thin && maxX - minX > CGFloat(width) * 0.85)
            || (maxX - minX < thin && maxY - minY > CGFloat(height) * 0.85)
    }

    private static func simplifyClosed(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        let stroke = points.map { StrokePoint(x: Float($0.x), y: Float($0.y), w: 0) }
        let simplified = GlyphProcessing.simplify(stroke, tolerance: Float(tolerance))
        let result = simplified.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        return result.count >= 3 ? result : points
    }

    static func percentile(_ values: [UInt8], _ fraction: Double) -> UInt8 {
        guard !values.isEmpty else { return 255 }
        var histogram = [Int](repeating: 0, count: 256)
        for value in values { histogram[Int(value)] += 1 }
        let target = Int(Double(values.count) * fraction)
        var running = 0
        for (value, count) in histogram.enumerated() {
            running += count
            if running > target { return UInt8(value) }
        }
        return 255
    }
}
