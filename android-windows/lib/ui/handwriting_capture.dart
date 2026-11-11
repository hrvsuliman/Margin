import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../handwriting/analysis.dart';
import '../handwriting/capture.dart';
import '../handwriting/handwriting_library.dart';
import '../handwriting/note_layout.dart';
import '../handwriting/page_painter.dart';
import 'theme.dart';
import 'widgets.dart';

/// What to write next in a capture session: one character, or the sample word.
class CaptureItem {
  const CaptureItem.character(this.text) : isWord = false;
  const CaptureItem.word(this.text) : isWord = true;
  final String text;
  final bool isWord;
}

abstract final class CaptureSessions {
  /// Everything not written yet, then the sample word if spacing wasn't measured.
  static List<CaptureItem> missing(HandwritingLibrary library, HandwritingProfile profile) {
    final have = library.capturedCharacters(profile.uid);
    return [
      for (final c in HandwritingCharset.all)
        if (!have.contains(c)) CaptureItem.character(c),
      if (!profile.spacingMeasured) const CaptureItem.word(HandwritingCharset.sampleWord),
    ];
  }

  /// Two extra versions of the most common letters.
  static List<CaptureItem> variants() => [
        for (final c in HandwritingCharset.variantLetters) ...[CaptureItem.character(c), CaptureItem.character(c)],
      ];
}

Future<void> startCapture(BuildContext context, String profileUid, List<CaptureItem> items, {String title = 'Handschrift'}) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CaptureScreen(profileUid: profileUid, items: items, title: title),
      ),
    );

/// Guided writing with the pen: one character (or the sample word) at a time, on guide lines.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.profileUid, required this.items, this.title = 'Handschrift'});
  final String profileUid;
  final List<CaptureItem> items;
  final String title;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _canvas = CaptureController();
  var _index = 0;
  var _saved = 0;
  double? _spacing;

  CaptureItem? get _item => _index < widget.items.length ? widget.items[_index] : null;

  @override
  void dispose() {
    _canvas.dispose();
    super.dispose();
  }

  void _save() {
    final item = _item;
    if (item == null) return;
    final strokes = GlyphProcessing.normalize(_canvas.strokes, _canvas.guide);
    if (strokes == null) return;
    final library = Services.handwriting;
    if (item.isWord) {
      _spacing = library.measureSpacing(widget.profileUid, item.text, strokes) ?? _spacing;
    } else {
      library.addGlyph(widget.profileUid, item.text, strokes);
      _saved++;
    }
    _advance();
  }

  void _advance() {
    _canvas.clear();
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _save,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _canvas.undo,
        const SingleActivator(LogicalKeyboardKey.delete): _canvas.clear,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: context.colors.paper,
          appBar: AppBar(
            title: Text(widget.title),
            automaticallyImplyLeading: false,
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fertig'))],
          ),
          body: item == null ? _finished(context) : _writing(context, item),
        ),
      ),
    );
  }

  Widget _writing(BuildContext context, CaptureItem item) {
    final secondary = TextStyle(color: context.colors.secondaryInk);
    final total = widget.items.length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              LinearProgressIndicator(value: total == 0 ? 0 : _index / total, color: context.colors.marginRed),
              const SizedBox(height: 6),
              Text('${_index + 1} von $total', style: secondary.copyWith(fontSize: 12)),
              const SizedBox(height: 10),
              Text(item.isWord ? 'Schreib dieses Wort in einem Zug:' : 'Schreib groß und langsam:', style: secondary),
              Text(item.text, style: context.serifTitle.copyWith(fontSize: item.isWord ? 34 : 56, fontWeight: FontWeight.w400)),
              Text(
                item.isWord
                    ? 'So weit auseinander, wie du normal schreibst. Daraus wird der Buchstabenabstand gemessen.'
                    : HandwritingCharset.hint(item.text),
                style: secondary.copyWith(fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: item.isWord ? 2.4 : 0.92,
                    child: Container(
                      decoration: BoxDecoration(
                        color: PageColors.paper,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.colors.ruling),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: StrokeCanvas(key: ValueKey('canvas-$_index'), controller: _canvas),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ListenableBuilder(
                listenable: _canvas,
                builder: (context, _) => Column(children: [
                  Row(children: [
                    IconButton(
                      tooltip: 'Rückgängig (Strg+Z)',
                      icon: const Icon(Icons.undo),
                      onPressed: _canvas.isEmpty ? null : _canvas.undo,
                    ),
                    IconButton(
                      tooltip: 'Löschen (Entf)',
                      icon: const Icon(Icons.cleaning_services_outlined),
                      onPressed: _canvas.isEmpty ? null : _canvas.clear,
                    ),
                    const Spacer(),
                    TextButton(onPressed: _advance, child: const Text('Überspringen')),
                  ]),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _canvas.isEmpty ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.ink,
                        foregroundColor: context.colors.paper,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(_index == total - 1 ? 'Sichern' : 'Weiter  (Enter)'),
                    ),
                  ),
                ]),
              ),
              if (!item.isWord) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 12, children: [
                  for (final next in widget.items.skip(_index + 1).take(12))
                    Text(next.text, style: context.serifTitle.copyWith(fontSize: 16, color: context.colors.faintInk)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _finished(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.verified_outlined, size: 48, color: context.colors.marginRed),
            const SizedBox(height: 12),
            Text('Geschafft', style: context.serifTitle.copyWith(fontSize: 28)),
            const SizedBox(height: 6),
            Text('$_saved Zeichen gespeichert.', style: TextStyle(color: context.colors.secondaryInk)),
            if (_spacing != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Gemessener Buchstabenabstand: ${_spacing!.toStringAsFixed(2)} × x-Höhe',
                    style: TextStyle(color: context.colors.secondaryInk, fontSize: 13)),
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Zur Vorschau')),
          ]),
        ),
      );
}

/// Holds what was written in a capture box.
class CaptureController extends ChangeNotifier {
  final List<List<CapturedPoint>> strokes = [];
  List<CapturedPoint>? current;

  /// Size of the writing area when the strokes were written (for the guide).
  Size size = Size.zero;

  bool get isEmpty => strokes.isEmpty;
  CaptureGuide get guide => CaptureGuide(size.width, size.height);

  void undo() {
    if (strokes.isEmpty) return;
    strokes.removeLast();
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    current = null;
    notifyListeners();
  }

  void _begin(CapturedPoint point, Size canvasSize) {
    size = canvasSize;
    current = [point];
    notifyListeners();
  }

  void _add(CapturedPoint point) {
    current?.add(point);
    notifyListeners();
  }

  void _end() {
    final stroke = current;
    current = null;
    if (stroke != null && stroke.isNotEmpty) strokes.add(stroke);
    notifyListeners();
  }
}

/// A writing area for the pen (or finger, or mouse), with guide lines underneath.
/// While a pen is in use, touches are ignored, so the hand can rest on the screen.
class StrokeCanvas extends StatefulWidget {
  const StrokeCanvas({super.key, required this.controller});
  final CaptureController controller;

  @override
  State<StrokeCanvas> createState() => _StrokeCanvasState();
}

class _StrokeCanvasState extends State<StrokeCanvas> {
  int? _pointer;
  var _penSeen = false;

  static bool _isPen(PointerEvent e) => e.kind == PointerDeviceKind.stylus;

  CapturedPoint _point(PointerEvent e) {
    double? pressure;
    if (_isPen(e) && e.pressureMax > e.pressureMin) {
      pressure = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
    }
    return CapturedPoint(e.localPosition.dx, e.localPosition.dy, e.timeStamp.inMicroseconds / 1e6, pressure);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (_pointer != null) return;
              // The pen's eraser end and the palm are not writing.
              if (e.kind == PointerDeviceKind.invertedStylus) return;
              if (e.kind == PointerDeviceKind.touch && _penSeen) return;
              if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
              if (_isPen(e)) _penSeen = true;
              _pointer = e.pointer;
              widget.controller._begin(_point(e), size);
            },
            onPointerMove: (e) {
              if (e.pointer == _pointer) widget.controller._add(_point(e));
            },
            onPointerUp: (e) {
              if (e.pointer != _pointer) return;
              widget.controller._add(_point(e));
              widget.controller._end();
              _pointer = null;
            },
            onPointerCancel: (e) {
              if (e.pointer != _pointer) return;
              widget.controller._end();
              _pointer = null;
            },
            child: CustomPaint(size: size, painter: _CanvasPainter(widget.controller)),
          );
        },
      );
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.controller) : super(repaint: controller);
  final CaptureController controller;

  static const _baseline = Color(0xFF7F9CC0);
  static const _guide = Color(0xFFA9BED6);
  static const _guideFaint = Color(0xFFD3DEEA);

  @override
  void paint(Canvas canvas, Size size) {
    final guide = CaptureGuide(size.width, size.height);
    void line(double y, Color color, double width, {double dash = 0, double gap = 0}) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = width;
      if (dash == 0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        return;
      }
      for (var x = 0.0; x < size.width; x += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      }
    }

    line(guide.capLine, _guideFaint, 1, dash: 3, gap: 5);
    line(guide.xLine, _guide, 1, dash: 6, gap: 5);
    line(guide.baseline, _baseline, 1.5);
    line(guide.descenderLine, _guideFaint, 1, dash: 3, gap: 5);

    final ink = PageColors.pen(PenColor.royalBlue);
    final width = size.height * 0.022 < 3 ? 3.0 : size.height * 0.022;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = ink;
    for (final points in [...controller.strokes, ?controller.current]) {
      if (points.isEmpty) continue;
      if (points.length < 3) {
        canvas.drawCircle(Offset(points.first.x, points.first.y), width / 2, dot);
        continue;
      }
      // Smooth through midpoints.
      final path = Path()..moveTo(points.first.x, points.first.y);
      for (var i = 1; i < points.length - 1; i++) {
        final c = points[i], n = points[i + 1];
        path.quadraticBezierTo(c.x, c.y, (c.x + n.x) / 2, (c.y + n.y) / 2);
      }
      path.lineTo(points.last.x, points.last.y);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => old.controller != controller;
}
