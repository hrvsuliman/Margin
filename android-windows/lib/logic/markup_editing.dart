// Formatting buttons of the note editor, as plain text operations.
// Ported from MarkupTextController in MarkupTextView.swift.

import 'markup.dart';

enum LineStyle {
  heading('# '),
  subheading('## '),
  bullet('- '),
  checkbox('- [ ] '),
  callout('> '),
  plain('');

  const LineStyle(this.prefix);
  final String prefix;
}

/// Text and cursor after an edit.
class TextEdit {
  const TextEdit(this.text, this.caret);
  final String text;
  final int caret;
}

abstract final class MarkupEditing {
  static int _clamp(int value, int low, int high) => value < low ? low : (value > high ? high : value);

  /// Start and end (after its newline) of the lines touched by the selection.
  static (int, int) lineRange(String text, int start, int end) {
    start = _clamp(start, 0, text.length);
    end = _clamp(end, start, text.length);
    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    // A selection ending right after a newline doesn't touch the next line.
    final last = end > start && text[end - 1] == '\n' ? end - 1 : end;
    final newline = text.indexOf('\n', last);
    return (lineStart, newline < 0 ? text.length : newline + 1);
  }

  static TextEdit _replaceLines(String text, int start, int end, String Function(String line) change) {
    final (lineStart, lineEnd) = lineRange(text, start, end);
    final block = text.substring(lineStart, lineEnd);
    final endsWithNewline = block.endsWith('\n');
    final lines = block.split('\n');
    if (endsWithNewline) lines.removeLast();
    final replacement = lines.map(change).join('\n') + (endsWithNewline ? '\n' : '');
    final result = text.replaceRange(lineStart, lineEnd, replacement);
    return TextEdit(result, lineStart + replacement.length - (endsWithNewline ? 1 : 0));
  }

  /// Applies a line style to every line touched by the selection.
  static TextEdit apply(LineStyle style, String text, int start, int end) => _replaceLines(text, start, end, (line) {
        final bare = Markup.stripMarker(line);
        return line.trim().isEmpty && style != LineStyle.plain ? style.prefix : style.prefix + bare;
      });

  /// Ticks or unticks the checkboxes on the selected lines ("- [ ] " ↔ "- [x] ");
  /// other lines become checkboxes.
  static TextEdit toggleCheckbox(String text, int start, int end) {
    final edit = _replaceLines(text, start, end, (line) {
      if (line.startsWith('- [ ] ')) return '- [x] ${line.substring(6)}';
      if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) return '- [ ] ${line.substring(6)}';
      return '- [ ] ${Markup.stripMarker(line)}';
    });
    // The cursor stays where it was (the line length doesn't change for a toggle).
    return TextEdit(edit.text, _clamp(start, 0, edit.text.length));
  }

  /// Inserts at the cursor, or appends after a blank line when there is no cursor.
  static TextEdit insert(String insertion, String text, int start, int end) {
    if (start < 0 || end < 0) {
      final prefix = text.isEmpty ? '' : (text.endsWith('\n') ? '\n' : '\n\n');
      final result = text + prefix + insertion;
      return TextEdit(result, result.length);
    }
    final from = _clamp(start, 0, text.length), to = _clamp(end, from, text.length);
    return TextEdit(text.replaceRange(from, to, insertion), from + insertion.length);
  }
}
