// The light markup of Margin notes, ported from NoteBlock.parse in
// Margin/Handwriting/NoteLayout.swift and NoteFlashcards in LearningEngines.swift.

sealed class NoteBlock {
  const NoteBlock();
}

class HeadingBlock extends NoteBlock {
  const HeadingBlock(this.text);
  final String text;
}

class SubheadingBlock extends NoteBlock {
  const SubheadingBlock(this.text);
  final String text;
}

class BulletBlock extends NoteBlock {
  const BulletBlock(this.text);
  final String text;
}

class CheckboxBlock extends NoteBlock {
  const CheckboxBlock(this.text, {required this.checked});
  final String text;
  final bool checked;
}

class CalloutBlock extends NoteBlock {
  const CalloutBlock(this.text);
  final String text;
}

class TableRowBlock extends NoteBlock {
  const TableRowBlock(this.cells);

  /// Empty for a `|---|---|` rule row.
  final List<String> cells;
}

class DividerBlock extends NoteBlock {
  const DividerBlock();
}

class ParagraphBlock extends NoteBlock {
  const ParagraphBlock(this.text);
  final String text;
}

class ImageBlock extends NoteBlock {
  const ImageBlock(this.uid);
  final String uid;
}

class BlankBlock extends NoteBlock {
  const BlankBlock();
}

abstract final class Markup {
  static const imagePrefix = '[[Bild:';
  static const checkboxMarkers = [
    ('- [ ] ', false),
    ('- [x] ', true),
    ('- [X] ', true),
    ('[ ] ', false),
    ('[x] ', true),
  ];
  static const bulletMarkers = ['- ', '• ', '* ', '– '];

  /// Longest first, so "- [ ] " is not mistaken for "- " (LineStyle.markers).
  static const lineMarkers = ['- [ ] ', '- [x] ', '- [X] ', '## ', '# ', '- ', '• ', '* ', '– ', '> '];

  static final _link = RegExp(r'\[\[(?!Bild:)([^\[\]]+)\]\]');
  static final _uuid = RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$');

  /// Titles of the notes linked with `[[Titel]]`, each once.
  static List<String> links(String text) {
    final seen = <String>{};
    final titles = <String>[];
    for (final match in _link.allMatches(text)) {
      final title = match.group(1)!.trim();
      if (title.isNotEmpty && seen.add(title.toLowerCase())) titles.add(title);
    }
    return titles;
  }

  /// `[[Titel]]` → `Titel`.
  static String stripLinks(String text) => text.replaceAllMapped(_link, (m) => m.group(1)!);

  static List<String> tableCells(String line) {
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (line.startsWith('|') && cells.isNotEmpty) cells.removeAt(0);
    if (line.endsWith('|') && cells.isNotEmpty) cells.removeLast();
    final isRule = cells.isNotEmpty && cells.every((c) => c.isNotEmpty && c.split('').every((ch) => ch == '-' || ch == ':'));
    return isRule ? const [] : cells;
  }

  static List<NoteBlock> parse(String text) => text.replaceAll('\r\n', '\n').split('\n').map(_line).toList();

  static NoteBlock _line(String raw) {
    var line = raw.trim();
    if (line.isEmpty) return const BlankBlock();
    if (line.startsWith(imagePrefix) && line.endsWith(']]')) {
      final id = line.substring(imagePrefix.length, line.length - 2);
      if (_uuid.hasMatch(id)) return ImageBlock(id.toUpperCase());
    }
    line = stripLinks(line);
    if (line == '---' || line == '***' || line == '___') return const DividerBlock();
    if (line.startsWith('|') && line.length > 1) return TableRowBlock(tableCells(line));
    for (final (marker, checked) in checkboxMarkers) {
      if (line.startsWith(marker)) return CheckboxBlock(line.substring(marker.length), checked: checked);
    }
    if (line.startsWith('> ')) return CalloutBlock(line.substring(2));
    if (line.startsWith('## ')) return SubheadingBlock(line.substring(3));
    if (line.startsWith('# ')) return HeadingBlock(line.substring(2));
    for (final marker in bulletMarkers) {
      if (line.startsWith(marker)) return BulletBlock(line.substring(marker.length));
    }
    return ParagraphBlock(line);
  }

  static String stripMarker(String line) {
    for (final marker in lineMarkers) {
      if (line.startsWith(marker)) return line.substring(marker.length);
    }
    return line;
  }

  /// Lines like `Begriff :: Erklärung` (list markers allowed) become flashcards.
  static List<(String, String)> flashcards(String body) {
    final cards = <(String, String)>[];
    for (final raw in body.split('\n')) {
      final line = stripMarker(raw.trim());
      final at = line.indexOf('::');
      if (at < 0) continue;
      final front = line.substring(0, at).trim();
      final back = line.substring(at + 2).trim();
      if (front.isNotEmpty && back.isNotEmpty) cards.add((front, back));
    }
    return cards;
  }

  /// Toggles the checkbox on line [index] ("- [ ] " ⇄ "- [x] ").
  static String toggleCheckbox(String body, int index) {
    final lines = body.split('\n');
    if (index < 0 || index >= lines.length) return body;
    final line = lines[index];
    final indent = line.length - line.trimLeft().length;
    final rest = line.substring(indent);
    for (final (marker, checked) in checkboxMarkers) {
      if (rest.startsWith(marker)) {
        final replacement = checked ? '- [ ] ' : '- [x] ';
        lines[index] = line.substring(0, indent) + replacement + rest.substring(marker.length);
        break;
      }
    }
    return lines.join('\n');
  }
}
