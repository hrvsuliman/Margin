import SwiftUI
import UIKit

/// Holds what was written in a capture box. Shared between the SwiftUI
/// buttons (undo, clear) and the UIKit drawing view.
final class CaptureController: ObservableObject {
    @Published private(set) var strokes: [[CapturedPoint]] = []
    /// Size of the drawing area when the strokes were written (for the guide).
    private(set) var canvasSize: CGSize = .zero
    fileprivate weak var view: CaptureUIView?

    var isEmpty: Bool { strokes.isEmpty }
    var guide: CaptureGuide { CaptureGuide(size: canvasSize) }

    func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        view?.setNeedsDisplay()
    }

    func clear() {
        strokes = []
        view?.setNeedsDisplay()
    }

    fileprivate func add(_ stroke: [CapturedPoint], canvasSize: CGSize) {
        self.canvasSize = canvasSize
        strokes.append(stroke)
    }
}

/// A writing area for finger input, with guide lines underneath.
struct StrokeCanvas: View {
    @ObservedObject var controller: CaptureController
    var showsGuides = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showsGuides {
                    GuideLines(guide: CaptureGuide(size: geometry.size))
                }
                CaptureRepresentable(controller: controller)
            }
        }
    }
}

/// Baseline (solid), x-height (dashed), cap height and descender (faint).
struct GuideLines: View {
    let guide: CaptureGuide

    var body: some View {
        Canvas { context, size in
            func line(_ y: CGFloat, color: Color, width: CGFloat, dash: [CGFloat] = []) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
            }
            line(guide.capLine, color: PaperInk.guideFaint, width: 1, dash: [3, 5])
            line(guide.xLine, color: PaperInk.guide, width: 1, dash: [6, 5])
            line(guide.baseline, color: PaperInk.baseline, width: 1.5)
            line(guide.descenderLine, color: PaperInk.guideFaint, width: 1, dash: [3, 5])
        }
        .accessibilityHidden(true)
    }
}

/// Fixed paper-like colours for writing surfaces (they stay light in dark mode,
/// like a real sheet of paper).
enum PaperInk {
    static let paper = Color(uiColor: PageRenderer.paperColor)
    static let ink = Color(uiColor: UIColor(hex: PenColor.royalBlue.hex))
    static let baseline = Color(uiColor: UIColor(hex: 0x7F9CC0))
    static let guide = Color(uiColor: UIColor(hex: 0xA9BED6))
    static let guideFaint = Color(uiColor: UIColor(hex: 0xD3DEEA))
}

private struct CaptureRepresentable: UIViewRepresentable {
    let controller: CaptureController

    func makeUIView(context: Context) -> CaptureUIView {
        let view = CaptureUIView()
        view.controller = controller
        controller.view = view
        return view
    }

    func updateUIView(_ uiView: CaptureUIView, context: Context) {
        uiView.controller = controller
        controller.view = uiView
        uiView.setNeedsDisplay()
    }
}

/// Records touches with coalesced samples (up to 120 per second) for smooth strokes.
final class CaptureUIView: UIView {
    weak var controller: CaptureController?
    private var current: [CapturedPoint] = []
    private let inkColor = UIColor(hex: PenColor.royalBlue.hex)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        current = [CapturedPoint(location: touch.location(in: self), time: touch.timestamp)]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            current.append(CapturedPoint(location: sample.location(in: self), time: sample.timestamp))
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            current.append(CapturedPoint(location: touch.location(in: self), time: touch.timestamp))
        }
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishStroke()
    }

    private func finishStroke() {
        if !current.isEmpty {
            controller?.add(current, canvasSize: bounds.size)
        }
        current = []
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let strokes = (controller?.strokes ?? []) + (current.isEmpty ? [] : [current])
        inkColor.setStroke()
        inkColor.setFill()
        let width = max(3, bounds.height * 0.022)
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            if stroke.count < 3 {
                UIBezierPath(ovalIn: CGRect(x: first.location.x - width / 2, y: first.location.y - width / 2,
                                            width: width, height: width)).fill()
                continue
            }
            let path = UIBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: first.location)
            // Smooth through midpoints.
            for index in 1..<(stroke.count - 1) {
                let current = stroke[index].location
                let next = stroke[index + 1].location
                path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), controlPoint: current)
            }
            path.addLine(to: stroke[stroke.count - 1].location)
            path.stroke()
        }
    }
}
