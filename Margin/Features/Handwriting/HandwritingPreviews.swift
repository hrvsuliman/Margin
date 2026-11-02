import SwiftUI

/// A strip of lined paper with text in the given handwriting.
struct HandwritingSampleView: View {
    let text: String
    let font: HandwritingFont?
    var lines = 3
    var lineSpacingMM: Double = 9

    @State private var page: LaidOutPage?
    @State private var settings = PageSettings()

    var body: some View {
        Canvas { context, size in
            guard let page else { return }
            context.withCGContext { cg in
                let scale = size.width / settings.pageSize.width
                cg.scaleBy(x: scale, y: scale)
                PageRenderer.draw(page, settings: settings, in: cg, includePaper: true)
            }
        }
        .aspectRatio(settings.pageSize.width / settings.pageSize.height, contentMode: .fit)
        .background(PaperInk.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if font == nil {
                ProgressView()
            }
        }
        .task(id: renderID) {
            guard let font else { return }
            var spec = PageSettings()
            spec.lineSpacing = PageSettings.mm(lineSpacingMM)
            spec.marginLeft = PageSettings.mm(8)
            spec.marginRight = PageSettings.mm(8)
            spec.marginTop = PageSettings.mm(2)
            spec.marginBottom = PageSettings.mm(1)
            spec.pageSize = CGSize(width: PageSettings.a4.width,
                                   height: spec.marginTop + spec.lineSpacing * (CGFloat(lines) + 0.6) + spec.marginBottom)
            spec.showHeader = false
            spec.showPageNumbers = false
            spec.showMarginLine = false
            let content = NoteContent(title: "", header: "", body: text, seed: 42)
            let finalSpec = spec
            let laidOut = await Task.detached(priority: .userInitiated) {
                NoteLayout.layout(content, settings: finalSpec, font: font).first
            }.value
            guard !Task.isCancelled else { return }
            settings = finalSpec
            page = laidOut
        }
        .accessibilityLabel("Vorschau: \(text)")
    }

    private var renderID: String {
        "\(text)-\(font.map { ObjectIdentifier($0).hashValue } ?? 0)-\(lines)"
    }
}

/// One glyph on guide lines, as in the capture box.
struct GlyphTile: View {
    let variant: HandwritingFont.Variant?
    let character: String
    var showsGuides = true

    var body: some View {
        Canvas { context, size in
            let guide = CaptureGuide(size: size)
            if showsGuides {
                for (y, opacity) in [(guide.xLine, 0.5), (guide.baseline, 0.9)] {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(PaperInk.guide.opacity(opacity)), lineWidth: 0.75)
                }
            }
            guard let variant else { return }
            let unit = guide.xHeight
            let width = variant.advance * unit
            let scale = width > size.width * 0.9 ? size.width * 0.9 / width : 1
            let transform = CGAffineTransform(scaleX: unit * scale, y: unit * scale)
                .concatenating(CGAffineTransform(translationX: (size.width - width * scale) / 2, y: guide.baseline))
            let path = Path(variant.outline).applying(transform)
            context.fill(path, with: .color(PaperInk.ink))
        }
        .background(PaperInk.paper)
        .overlay {
            if variant == nil {
                Text(character)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.faintInk)
            }
        }
        .accessibilityLabel(variant == nil ? "\(character), fehlt" : character)
    }
}

/// Builds a profile's font in the background whenever the profile changes.
struct ProfileFontLoader: ViewModifier {
    let profile: HandwritingProfile
    var penRatio: CGFloat = 0.15
    @Binding var font: HandwritingFont?

    func body(content: Content) -> some View {
        content.task(id: profile.updatedAt) {
            // Short pause so a slider drag only renders once it settles.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let source = FontSource(profile: profile)
            let ratio = penRatio
            let built = await Task.detached(priority: .userInitiated) {
                HandwritingFont(source: source, penRatio: ratio)
            }.value
            guard !Task.isCancelled else { return }
            font = built
        }
    }
}

extension View {
    func loadsFont(of profile: HandwritingProfile, into font: Binding<HandwritingFont?>) -> some View {
        modifier(ProfileFontLoader(profile: profile, font: font))
    }
}
