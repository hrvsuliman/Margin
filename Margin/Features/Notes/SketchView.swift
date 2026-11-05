import PencilKit
import SwiftUI

/// Draw a diagram, formula or sketch with a finger or Apple Pencil.
/// Saved as a transparent picture block, drawn straight onto the page (no tape, no frame).
struct SketchView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (UIImage, CGSize) -> Void

    @State private var canvas = PKCanvasView()
    @State private var fingerDraws = true

    var body: some View {
        NavigationStack {
            SketchCanvas(canvas: canvas, fingerDraws: fingerDraws)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Skizze")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Einfügen") { save() }
                            .disabled(canvas.drawing.strokes.isEmpty)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            canvas.undoManager?.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .accessibilityLabel("Rückgängig")
                        Spacer()
                        Toggle(isOn: $fingerDraws) {
                            Label("Mit dem Finger zeichnen", systemImage: "hand.draw")
                        }
                        .toggleStyle(.button)
                        .accessibilityHint("Aus: nur der Apple Pencil zeichnet, der Finger scrollt")
                    }
                }
        }
        .tint(Palette.marginRed)
    }

    private func save() {
        let drawing = canvas.drawing
        let bounds = drawing.bounds.insetBy(dx: -12, dy: -12)
        guard !bounds.isEmpty else { return }
        // Render in light mode, so black ink stays black on paper even when the phone is in dark mode.
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 3)
        }
        onSave(image, bounds.size)
        dismiss()
    }
}

private struct SketchCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    let fingerDraws: Bool

    final class Coordinator {
        let picker = PKToolPicker()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        canvas.alwaysBounceVertical = true
        canvas.contentSize = CGSize(width: 2000, height: 2000)
        context.coordinator.picker.overrideUserInterfaceStyle = .light
        context.coordinator.picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        view.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
    }
}
