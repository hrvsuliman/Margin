import SwiftUI

/// A sheet of ruled notebook paper with a red margin line. Used as a background.
struct RuledPaper: View {
    var lineSpacing: CGFloat = 34
    var marginX: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            var y = lineSpacing * 2
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Palette.ruling), lineWidth: 0.75)
                y += lineSpacing
            }

            var margin = Path()
            margin.move(to: CGPoint(x: marginX, y: 0))
            margin.addLine(to: CGPoint(x: marginX, y: size.height))
            context.stroke(margin, with: .color(Palette.marginRed.opacity(0.55)), lineWidth: 1)
        }
        .background(Palette.paper)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
