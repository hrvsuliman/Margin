import 'package:flutter/material.dart';

import '../handwriting/analysis.dart';
import '../handwriting/capture.dart';
import '../handwriting/handwriting_font.dart';
import '../handwriting/handwriting_library.dart';
import '../handwriting/note_layout.dart';
import '../handwriting/page_painter.dart';
import 'handwriting_capture.dart';
import 'handwriting_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// A handwriting profile: preview, analysis, fine-tuning and all characters.
class ProfileDetailScreen extends StatelessWidget {
  const ProfileDetailScreen({super.key, required this.profileUid});
  final String profileUid;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Services.handwriting,
        builder: (context, _) {
          final library = Services.handwriting;
          final profile = library.profile(profileUid);
          if (profile == null) return const Scaffold();
          final font = library.font(profileUid, 0.15);
          final analysis = font.analysis;
          final secondary = TextStyle(color: context.colors.secondaryInk, fontSize: 13);
          final isDefault = library.defaultProfile?.uid == profileUid;

          return Scaffold(
            appBar: AppBar(title: Text(profile.displayName)),
            body: PageBody(maxWidth: 820, children: [
              const SizedBox(height: 8),
              Group(padding: const EdgeInsets.all(12), children: [
                _NameField(profile: profile),
                HandwritingPreview(profileUid: profileUid, text: HandwritingCharset.pangram),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Standard für neue Notizen'),
                  value: isDefault,
                  onChanged: (on) {
                    if (on) library.setDefault(profileUid);
                  },
                ),
              ]),
              const SectionTitle('Mit dem Stift'),
              Group(children: [
                if (analysis.missing.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text('Fehlende Zeichen schreiben (${analysis.missing.length})'),
                    onTap: () => startCapture(context, profileUid, CaptureSessions.missing(library, profile),
                        title: 'Zeichen schreiben'),
                  )
                else if (!profile.spacingMeasured)
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: const Text('Probewort schreiben (Abstand messen)'),
                    onTap: () => startCapture(context, profileUid, const [CaptureItem.word(HandwritingCharset.sampleWord)],
                        title: 'Probewort'),
                  ),
                ListTile(
                  leading: const Icon(Icons.layers_outlined),
                  title: const Text('Varianten schreiben'),
                  subtitle: const Text('Mehrere Versionen eines Buchstabens sorgen dafür, dass Wiederholungen nicht wie kopiert aussehen.'),
                  onTap: () => startCapture(context, profileUid, CaptureSessions.variants(), title: 'Varianten'),
                ),
              ]),
              const SectionTitle('Analyse'),
              Group(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                _Row('Zeichen', '${analysis.captured} von ${analysis.total}'),
                _Row('Schriftproben', '${analysis.variantCount}'),
                _Row('Größe', _sizeText(analysis.scaleCorrection)),
                _Row('Neigung', _slantText(analysis.slantDegrees)),
                _Row('Gleichmäßigkeit', '${(analysis.consistency * 100).round()} %'),
                _Row('Buchstabenabstand', profile.spacingMeasured ? 'gemessen' : 'Standardwert'),
                if (analysis.outliers.isNotEmpty)
                  ListTile(
                    title: Text('Auffällig groß oder klein: ${({for (final o in analysis.outliers) o.character}.toList()..sort()).join(' ')}'),
                    trailing: TextButton(
                      onPressed: () => library.fixOutliers(analysis.outliers),
                      child: const Text('Größe angleichen'),
                    ),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text('Größe und Grundlinie werden automatisch ausgeglichen, damit alle Zeichen gleich hoch auf der Linie stehen.',
                    style: secondary),
              ),
              const SectionTitle('Feinabstimmung'),
              Group(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                _Slider('Buchstabenabstand', profile.letterSpacing, 0, 0.8, (v) => library.updateProfile(profileUid, {'letterSpacing': v})),
                _Slider('Wortabstand', profile.wordSpacing, 0.3, 1.8, (v) => library.updateProfile(profileUid, {'wordSpacing': v})),
                _Slider('Neigung', profile.slantAdjust, -15, 15, (v) => library.updateProfile(profileUid, {'slantAdjust': v}), unit: '°'),
                _Slider('Natürliche Variation', profile.variation, 0, 2, (v) => library.updateProfile(profileUid, {'variation': v})),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => library.updateProfile(profileUid, {
                      'letterSpacing': 0.14, 'wordSpacing': 0.75, 'slantAdjust': 0.0, 'variation': 1.0, 'spacingMeasured': false,
                    }),
                    child: const Text('Zurücksetzen'),
                  ),
                ),
              ]),
              for (final (title, characters) in HandwritingCharset.groups) ...[
                SectionTitle(title),
                GridView.extent(
                  maxCrossAxisExtent: 76,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.9,
                  children: [
                    for (final c in characters)
                      _CharacterTile(
                        character: c,
                        variant: font.variants(c)?.first,
                        count: library.samples(profileUid, c).length,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => GlyphDetailScreen(profileUid: profileUid, character: c)),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: context.colors.marginRed),
                  onPressed: () async {
                    final ok = await confirm(context, 'Handschrift löschen?',
                        message: 'Alle Schriftproben dieses Profils werden gelöscht.');
                    if (ok && context.mounted) {
                      Navigator.pop(context);
                      library.delete(profileUid);
                    }
                  },
                  child: const Text('Handschrift löschen'),
                ),
              ),
            ]),
          );
        },
      );

  static String _sizeText(double correction) {
    if ((correction - 1).abs() < 0.05) return 'passt zu den Linien';
    return correction > 1
        ? 'kleiner geschrieben, ×${correction.toStringAsFixed(2)} vergrößert'
        : 'größer geschrieben, ×${correction.toStringAsFixed(2)} verkleinert';
  }

  static String _slantText(double degrees) {
    if (degrees.abs() < 2) return 'aufrecht';
    return '${degrees.abs().round()}° nach ${degrees > 0 ? 'rechts' : 'links'}';
  }
}

class _NameField extends StatefulWidget {
  const _NameField({required this.profile});
  final HandwritingProfile profile;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _controller = TextEditingController(text: widget.profile.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        style: context.serifTitle,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (v) => Services.handwriting.updateProfile(widget.profile.uid, {'name': v}),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.value);
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(title),
        trailing: Text(value, style: TextStyle(color: context.colors.secondaryInk)),
      );
}

class _Slider extends StatelessWidget {
  const _Slider(this.title, this.value, this.min, this.max, this.onChanged, {this.unit = ''});
  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title)),
            Text('${value.toStringAsFixed(2)}$unit', style: TextStyle(color: context.colors.secondaryInk, fontSize: 13)),
          ]),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ]),
      );
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.character, required this.variant, required this.count, required this.onTap});
  final String character;
  final GlyphVariant? variant;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(fit: StackFit.expand, children: [
            GlyphTile(variant: variant, character: character),
            if (count > 1)
              Positioned(
                top: 3,
                right: 4,
                child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.colors.secondaryInk)),
              ),
          ]),
        ),
      );
}

/// One glyph on guide lines; the character in grey when it isn't written yet.
class GlyphTile extends StatelessWidget {
  const GlyphTile({super.key, required this.variant, required this.character});
  final GlyphVariant? variant;
  final String character;

  @override
  Widget build(BuildContext context) => Container(
        color: PageColors.paper,
        alignment: Alignment.center,
        child: variant == null
            ? Text(character, style: context.serifTitle.copyWith(fontSize: 20, color: Colors.black26, fontWeight: FontWeight.w400))
            : CustomPaint(size: Size.infinite, painter: _GlyphPainter(variant!)),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.variant);
  final GlyphVariant variant;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = CaptureGuide(size.width, size.height);
    for (final (y, opacity) in [(guide.xLine, 0.5), (guide.baseline, 0.9)]) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0xFFA9BED6).withValues(alpha: opacity)
          ..strokeWidth = 0.75,
      );
    }
    final unit = guide.xHeight;
    final width = variant.advance * unit;
    final scale = width > size.width * 0.9 ? size.width * 0.9 / width : 1.0;
    final dx = (size.width - width * scale) / 2;
    final path = Path()..fillType = PathFillType.nonZero;
    for (final polygon in variant.outline) {
      path.moveTo(polygon[0].x * unit * scale + dx, polygon[0].y * unit * scale + guide.baseline);
      for (var i = 1; i < polygon.length; i++) {
        path.lineTo(polygon[i].x * unit * scale + dx, polygon[i].y * unit * scale + guide.baseline);
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = PageColors.pen(PenColor.royalBlue));
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => !identical(old.variant, variant);
}

/// All versions of one character, with size and baseline correction.
class GlyphDetailScreen extends StatelessWidget {
  const GlyphDetailScreen({super.key, required this.profileUid, required this.character});
  final String profileUid;
  final String character;

  String get _contextWord {
    const words = ['Handschrift', 'Mathematik', 'Physik', 'Grundlagen', 'Übung', 'Zwölf', 'Jahr', 'Quiz', 'Vokabel'];
    return words.firstWhere((w) => w.contains(character), orElse: () => 'Schule');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Services.handwriting,
        builder: (context, _) {
          final library = Services.handwriting;
          final samples = library.samples(profileUid, character);
          final font = library.font(profileUid, 0.15);
          final secondary = TextStyle(color: context.colors.secondaryInk);
          return Scaffold(
            appBar: AppBar(title: Text('„$character“')),
            body: PageBody(maxWidth: 640, children: [
              const SizedBox(height: 8),
              HandwritingPreview(profileUid: profileUid, text: '$character$character$character $_contextWord', lines: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(HandwritingCharset.hint(character), style: secondary),
              ),
              if (samples.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Dieses Zeichen hast du noch nicht geschrieben. Bis dahin erscheint es in einer Ersatzschrift.',
                      style: secondary),
                ),
              for (var i = 0; i < samples.length; i++) ...[
                SectionTitle('Version ${i + 1}'),
                Group(padding: const EdgeInsets.all(8), children: [
                  SizedBox(
                    height: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GlyphTile(
                        variant: HandwritingFont.makeVariant(HandwritingLibrary.input(samples[i]), font.analysis, font.penRatio),
                        character: character,
                      ),
                    ),
                  ),
                  _Slider('Größe', samples[i].scale, 0.5, 1.8, (v) => library.updateGlyph(samples[i].uid, scale: v)),
                  _Slider('Höhe auf der Linie', samples[i].baselineOffset, -0.5, 0.5,
                      (v) => library.updateGlyph(samples[i].uid, baselineOffset: v)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(foregroundColor: context.colors.marginRed),
                      onPressed: () => library.deleteGlyph(samples[i].uid),
                      child: const Text('Version löschen'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(samples.isEmpty ? 'Jetzt schreiben' : 'Weitere Version schreiben'),
                  onPressed: () => startCapture(context, profileUid, [CaptureItem.character(character)], title: '„$character“'),
                ),
              ),
            ]),
          );
        },
      );
}
