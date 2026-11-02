import SwiftUI
import UIKit

/// The kind of a line in the note source.
enum LineStyle: CaseIterable {
    case heading, subheading, bullet, checkbox, callout, plain

    var prefix: String {
        switch self {
        case .heading: "# "
        case .subheading: "## "
        case .bullet: "- "
        case .checkbox: "- [ ] "
        case .callout: "> "
        case .plain: ""
        }
    }

    /// Longest markers first, so "- [ ] " is not mistaken for "- ".
    static let markers = ["- [ ] ", "- [x] ", "- [X] ", "## ", "# ", "- ", "• ", "* ", "– ", "> "]

    static func strip(_ line: String) -> String {
        for prefix in markers where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return line
    }
}

/// Lets SwiftUI buttons act on the text view (format the current line, insert text).
final class MarkupTextController: ObservableObject {
    fileprivate weak var textView: UITextView?

    /// Applies a line style to every line touched by the selection.
    func apply(_ style: LineStyle) {
        guard let textView else { return }
        let text = textView.text as NSString
        let selection = textView.selectedRange
        let lineRange = text.lineRange(for: selection)
        let block = text.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        let styled = lines.map { line -> String in
            let bare = LineStyle.strip(line)
            return line.trimmingCharacters(in: .whitespaces).isEmpty && style != .plain ? style.prefix : style.prefix + bare
        }
        let replacement = styled.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        replace(lineRange, with: replacement, in: textView)
        let caret = lineRange.location + (replacement as NSString).length - (endsWithNewline ? 1 : 0)
        textView.selectedRange = NSRange(location: max(0, caret), length: 0)
        Haptics.selection()
    }

    /// Ticks or unticks the checkboxes on the selected lines ("- [ ] " ↔ "- [x] ").
    func toggleCheckbox() {
        guard let textView else { return }
        let text = textView.text as NSString
        let selection = textView.selectedRange
        let lineRange = text.lineRange(for: selection)
        let block = text.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        let toggled = lines.map { line -> String in
            if line.hasPrefix("- [ ] ") { return "- [x] " + line.dropFirst(6) }
            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") { return "- [ ] " + line.dropFirst(6) }
            return "- [ ] " + LineStyle.strip(line)
        }
        let replacement = toggled.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        replace(lineRange, with: replacement, in: textView)
        textView.selectedRange = NSRange(location: min(selection.location, (textView.text as NSString).length), length: 0)
        Haptics.selection()
    }

    /// Inserts text at the cursor (or appends with a blank line before it if nothing is focused).
    func insert(_ insertion: String) {
        guard let textView else { return }
        let range = textView.isFirstResponder ? textView.selectedRange
            : NSRange(location: (textView.text as NSString).length, length: 0)
        let prefix = !textView.isFirstResponder && !textView.text.isEmpty ? "\n\n" : ""
        replace(range, with: prefix + insertion, in: textView)
    }

    func endEditing() {
        textView?.resignFirstResponder()
    }

    private func replace(_ range: NSRange, with replacement: String, in textView: UITextView) {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return }
        // Going through UITextInput keeps undo working.
        textView.replace(textRange, withText: replacement)
        // Make sure styling and the SwiftUI binding follow the programmatic change.
        textView.delegate?.textViewDidChange?(textView)
    }
}

/// A plain-text editor that shows headings and list items styled while typing.
struct MarkupTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkupTextController
    var placeholder = "Schreib oder füge Text ein …"

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = MarkupStyler.bodyFont
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 40, right: 12)
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.autocapitalizationType = .sentences
        view.smartQuotesType = .yes
        view.text = text
        MarkupStyler.style(view)
        controller.textView = view
        context.coordinator.placeholderLabel.text = placeholder
        context.coordinator.attachPlaceholder(to: view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        controller.textView = view
        if view.text != text {
            view.text = text
            MarkupStyler.style(view)
        }
        context.coordinator.updatePlaceholder(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        let placeholderLabel = UILabel()

        init(text: Binding<String>) {
            self.text = text
        }

        func attachPlaceholder(to view: UITextView) {
            placeholderLabel.font = MarkupStyler.bodyFont
            placeholderLabel.textColor = .placeholderText
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                placeholderLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
                placeholderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 17),
            ])
            updatePlaceholder(view)
        }

        func updatePlaceholder(_ view: UITextView) {
            placeholderLabel.isHidden = !view.text.isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            MarkupStyler.style(textView)
            updatePlaceholder(textView)
            if text.wrappedValue != textView.text {
                text.wrappedValue = textView.text
            }
        }
    }
}

/// Styles the source text: headings larger in serif, markers greyed out.
enum MarkupStyler {
    static let bodyFont = UIFont.preferredFont(forTextStyle: .body)

    static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static let headingFont = serif(.title2, weight: .semibold)
    private static let subheadingFont = serif(.headline, weight: .semibold)
    private static let linkRegex = try? NSRegularExpression(pattern: #"\[\[(?!Bild:)[^\[\]]+\]\]"#)

    static func style(_ view: UITextView) {
        let storage = view.textStorage
        let text = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes([.font: bodyFont, .foregroundColor: UIColor.label], range: NSRange(location: 0, length: text.length))
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = text.substring(with: range)
            var markerLength = 0
            var font: UIFont?
            if line.hasPrefix("## ") {
                markerLength = 3
                font = subheadingFont
            } else if line.hasPrefix("# ") {
                markerLength = 2
                font = headingFont
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                markerLength = 6
                if line.hasPrefix("- [ ] ") == false {
                    storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            } else if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
                markerLength = 2
            } else if line.hasPrefix("> ") {
                markerLength = 2
                font = serif(.body, weight: .regular)
                storage.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: range)
            } else if line.hasPrefix("|") || line == "---" {
                font = .monospacedSystemFont(ofSize: bodyFont.pointSize * 0.9, weight: .regular)
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
            } else if line.hasPrefix(NoteBlock.imagePrefix) {
                markerLength = range.length
                font = UIFont.preferredFont(forTextStyle: .caption1)
            }
            if let font {
                storage.addAttribute(.font, value: font, range: range)
            }
            if markerLength > 0 {
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel,
                                     range: NSRange(location: range.location, length: min(markerLength, range.length)))
            }
        }
        // [[Links]] to other notes in the margin red.
        if let regex = linkRegex {
            for match in regex.matches(in: storage.string, range: NSRange(location: 0, length: text.length)) {
                storage.addAttribute(.foregroundColor, value: UIColor(Palette.marginRed), range: match.range)
            }
        }
        storage.endEditing()
        view.typingAttributes = [.font: bodyFont, .foregroundColor: UIColor.label]
    }
}
