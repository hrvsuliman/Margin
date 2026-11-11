import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/dates.dart';
import '../data/entities.dart';
import '../handwriting/handwriting_library.dart';
import '../handwriting/note_layout.dart';
import '../handwriting/note_rendering.dart';
import '../handwriting/page_painter.dart';
import '../logic/markup_editing.dart';
import '../logic/note_pages.dart';
import 'handwriting_screen.dart';
import 'notes_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Text on the left, the note in your handwriting on the right (tabs on phones).
/// The text is the source of truth; the pages are set again after every change.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.noteUid});
  final String noteUid;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final String _initialBody;
  final _bodyFocus = FocusNode();
  Timer? _saveTimer;
  Timer? _layoutTimer;
  List<LaidOutPage> _pages = const [];
  PageSettings _settings = const PageSettings();
  String _layoutKey = '';

  Note? get _note => store.note(widget.noteUid);

  @override
  void initState() {
    super.initState();
    final note = _note;
    _title = TextEditingController(text: note?.title ?? '');
    _body = TextEditingController(text: note?.body ?? '');
    _initialBody = _body.text;
    Services.store.addListener(_dataChanged);
    Services.handwriting.addListener(_relayoutNow);
    _relayoutNow();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _layoutTimer?.cancel();
    Services.store.removeListener(_dataChanged);
    Services.handwriting.removeListener(_relayoutNow);
    // Save after the tree has settled (saving notifies other widgets).
    final uid = widget.noteUid, title = _title.text, body = _body.text;
    final edited = body != _initialBody;
    Future.microtask(() {
      _save(uid, title, body);
      // "Begriff :: Erklärung" lines become flashcards when leaving a note that was edited here.
      final note = store.note(uid);
      if (note != null && edited) store.syncCards(note);
    });
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Settings, subject or handwriting changed (here or through sync): set the pages again.
  void _dataChanged() {
    final note = _note;
    if (note == null) {
      if (mounted) Navigator.maybePop(context);
      return;
    }
    if (_keyOf(note) != _layoutKey) _relayoutNow();
  }

  String _keyOf(Note note) {
    final d = note.rec.data;
    return [
      for (final key in const [
        'paper', 'lineSpacingMM', 'writingSize', 'penColor', 'penWeight', 'marginTopMM', 'marginBottomMM',
        'marginLeftMM', 'marginRightMM', 'showMarginLine', 'showPageNumbers', 'showHeader', 'printPaper', 'seed',
        'profile', 'subject', 'noteDate',
      ])
        '${d[key]}',
      store.subject(note.subject)?.name ?? '',
    ].join('|');
  }

  void _textChanged() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
    _layoutTimer?.cancel();
    _layoutTimer = Timer(const Duration(milliseconds: 250), _relayoutNow);
  }

  void _saveNow() => _save(widget.noteUid, _title.text, _body.text);

  static void _save(String uid, String title, String body) {
    final note = store.note(uid);
    if (note == null || (note.title == title && note.body == body)) return;
    store.update(note.rec, (d) {
      d['title'] = title;
      d['body'] = body;
      d['updatedAt'] = isoDate(DateTime.now());
    });
  }

  void _relayoutNow() {
    final note = _note;
    if (note == null || !mounted) return;
    setState(() {
      _layoutKey = _keyOf(note);
      _settings = PageSettings.fromNote(note.rec.data);
      _pages = NoteRendering.layout(note, store, Services.handwriting, title: _title.text, body: _body.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    if (note == null) return const Scaffold();
    final wide = isWide(context);
    final actions = [
      IconButton(
        tooltip: 'Neu mischen',
        icon: const Icon(Icons.shuffle),
        onPressed: () => store.update(note.rec, (d) => d['seed'] = Random().nextInt(999999) + 1),
      ),
      IconButton(
        tooltip: 'Papier & Stift',
        icon: const Icon(Icons.tune),
        onPressed: () => showNoteSettings(context, note.uid),
      ),
      IconButton(
        tooltip: 'Als PDF sichern',
        icon: const Icon(Icons.picture_as_pdf_outlined),
        onPressed: () {
          _saveNow();
          exportNotePdf(context, note);
        },
      ),
    ];

    final editor = _TextPane(noteUid: note.uid, title: _title, body: _body, bodyFocus: _bodyFocus, onChanged: _textChanged);
    final pages = _PagesPane(pages: _pages, settings: _settings);

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: Text(note.displayTitle), actions: actions),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: editor),
            VerticalDivider(width: 1, color: context.colors.ruling),
            Expanded(flex: 6, child: pages),
          ],
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(note.displayTitle),
          actions: actions,
          bottom: const TabBar(tabs: [Tab(text: 'Text'), Tab(text: 'Handschrift')]),
        ),
        body: TabBarView(children: [editor, pages]),
      ),
    );
  }
}

class _TextPane extends StatelessWidget {
  const _TextPane({
    required this.noteUid,
    required this.title,
    required this.body,
    required this.bodyFocus,
    required this.onChanged,
  });
  final String noteUid;
  final TextEditingController title;
  final TextEditingController body;
  final FocusNode bodyFocus;
  final VoidCallback onChanged;

  /// Runs a formatting operation on the text at the cursor (or at the end).
  void _edit(TextEdit Function(String text, int start, int end) change) {
    final value = body.value;
    final selection = value.selection;
    final edit = change(value.text, selection.isValid ? selection.start : -1, selection.isValid ? selection.end : -1);
    body.value = TextEditingValue(text: edit.text, selection: TextSelection.collapsed(offset: edit.caret));
    bodyFocus.requestFocus();
    onChanged();
  }

  void _style(LineStyle style) => _edit((text, start, end) {
        final at = start < 0 ? text.length : start;
        return MarkupEditing.apply(style, text, at, end < 0 ? at : end);
      });

  void _checkbox() => _edit((text, start, end) {
        final at = start < 0 ? text.length : start;
        return MarkupEditing.toggleCheckbox(text, at, end < 0 ? at : end);
      });

  void _insert(String insertion) => _edit((text, start, end) => MarkupEditing.insert(insertion, text, start, end));

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              onChanged: (_) => onChanged(),
              style: context.serifTitle.copyWith(fontSize: 24),
              decoration: const InputDecoration(hintText: 'Titel', border: InputBorder.none, filled: false),
              textInputAction: TextInputAction.next,
            ),
            _PagesBar(noteUid: noteUid),
            _FormatBar(noteUid: noteUid, onStyle: _style, onCheckbox: _checkbox, onInsert: _insert),
            Divider(height: 1, color: context.colors.ruling),
            const SizedBox(height: 6),
            Expanded(
              child: TextField(
                controller: body,
                focusNode: bodyFocus,
                onChanged: (_) => onChanged(),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 16, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'Schreib los …\n\n# Überschrift\n## Zwischenüberschrift\n- Liste\n- [ ] Checkliste\n'
                      '> Merkkasten\n| Tabelle | Spalte |\n---\n[[Andere Notiz]]\nBegriff :: Erklärung (wird eine Karteikarte)',
                  hintStyle: TextStyle(color: context.colors.faintInk),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Heading, list, checklist and the "+" insertions (iPhone: keyboard bar).
class _FormatBar extends StatelessWidget {
  const _FormatBar({required this.noteUid, required this.onStyle, required this.onCheckbox, required this.onInsert});
  final String noteUid;
  final ValueChanged<LineStyle> onStyle;
  final VoidCallback onCheckbox;
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    Widget button(String tooltip, IconData icon, VoidCallback onPressed) => IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        button('Überschrift', Icons.title, () => onStyle(LineStyle.heading)),
        button('Zwischenüberschrift', Icons.text_fields, () => onStyle(LineStyle.subheading)),
        button('Liste', Icons.format_list_bulleted, () => onStyle(LineStyle.bullet)),
        button('Checkliste (noch mal tippen zum Abhaken)', Icons.checklist, onCheckbox),
        button('Merkkasten', Icons.format_quote, () => onStyle(LineStyle.callout)),
        button('Tabelle', Icons.table_chart_outlined, () => onInsert('| Spalte | Spalte |\n|---|---|\n| | |\n')),
        button('Trennlinie', Icons.horizontal_rule, () => onInsert('---\n')),
        button('Normaler Text', Icons.format_clear, () => onStyle(LineStyle.plain)),
        PopupMenuButton<String>(
          tooltip: 'Link zu Notiz',
          icon: const Icon(Icons.link, size: 20),
          onSelected: (title) => onInsert('[[$title]]'),
          itemBuilder: (_) => [
            for (final note in store.notes.where((n) => n.uid != noteUid && n.title.trim().isNotEmpty).take(30))
              PopupMenuItem(value: note.title.trim(), child: Text(note.title.trim())),
            const PopupMenuItem(value: 'Neue Seite', child: Text('Neue Seite …')),
          ],
        ),
      ],
    );
  }
}

/// Parent, subpages, links and backlinks of a note, as chips above the text.
class _PagesBar extends StatelessWidget {
  const _PagesBar({required this.noteUid});
  final String noteUid;

  @override
  Widget build(BuildContext context) => StoreBuilder(builder: (context, store) {
        final note = store.note(noteUid);
        if (note == null) return const SizedBox();
        final parent = store.parentOf(noteUid);
        final children = store.childrenOf(noteUid);
        final linked = store.linkedFrom(note);
        final missing = store.missingLinks(note);
        final backlinks = store.backlinksTo(note);
        final dashed = BorderSide(color: context.colors.ruling);
        Widget chip(Note other, IconData icon) => ActionChip(
              avatar: Icon(icon, size: 16),
              label: Text(other.displayTitle, overflow: TextOverflow.ellipsis),
              onPressed: () => openNote(context, other.uid),
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if (parent != null) chip(parent, Icons.arrow_upward),
            for (final child in children) chip(child, Icons.description_outlined),
            for (final other in linked) chip(other, Icons.link),
            for (final title in missing)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                side: dashed,
                label: Text(title, overflow: TextOverflow.ellipsis),
                tooltip: 'Legt die verlinkte Seite an',
                onPressed: () => openNote(context, store.addSubpage(noteUid, title: title).uid),
              ),
            if (backlinks.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Erwähnt in',
                onSelected: (uid) => openNote(context, uid),
                itemBuilder: (_) => [
                  for (final other in backlinks) PopupMenuItem(value: other.uid, child: Text(other.displayTitle)),
                ],
                child: Chip(avatar: const Icon(Icons.undo, size: 16), label: Text('Erwähnt in ${backlinks.length}')),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              side: dashed,
              label: const Text('Unterseite'),
              onPressed: () => openNote(context, store.addSubpage(noteUid).uid),
            ),
          ]),
        );
      });
}

class _PagesPane extends StatelessWidget {
  const _PagesPane({required this.pages, required this.settings});
  final List<LaidOutPage> pages;
  final PageSettings settings;

  @override
  Widget build(BuildContext context) {
    final missing = <String>{
      for (final page in pages)
        for (final fallback in page.fallbacks)
          for (final rune in fallback.text.runes) String.fromCharCode(rune),
    };
    final hasHandwriting = Services.handwriting.profiles.isNotEmpty;
    return Container(
      color: context.colors.paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          if (!hasHandwriting)
            _Hint(
              text: 'Noch ohne deine Handschrift. Lade sie aus einem iPhone-Backup.',
              action: 'Handschrift',
              onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HandwritingScreen())),
            )
          else if (missing.isNotEmpty)
            _Hint(text: 'Noch nicht geschrieben (in Druckschrift): ${missing.join(' ')}'),
          for (final page in pages)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: AspectRatio(
                    aspectRatio: settings.pageWidth / settings.pageHeight,
                    child: RepaintBoundary(child: CustomPaint(painter: NotePagePainter(page, settings))),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: context.colors.secondaryInk),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: context.colors.secondaryInk))),
            if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}

/// Paper, pen and layout of a note ("Papier & Stift"). Changes show live on the pages.
Future<void> showNoteSettings(BuildContext context, String noteUid) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scroll) => _NoteSettings(noteUid: noteUid, scroll: scroll),
      ),
    );

class _NoteSettings extends StatelessWidget {
  const _NoteSettings({required this.noteUid, required this.scroll});
  final String noteUid;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Services.store, Services.handwriting]),
        builder: (context, _) {
          final note = store.note(noteUid);
          if (note == null) return const SizedBox();
          final d = note.rec.data;
          double number(String key, double fallback) => d[key] is num ? (d[key] as num).toDouble() : fallback;
          bool flag(String key) => d[key] is bool ? d[key] as bool : true;
          void put(String key, Object? value) => store.update(note.rec, (data) => data[key] = value);

          final paper = PaperStyle.parse(d['paper'] as String?);
          final pen = PenColor.parse(d['penColor'] as String?);
          final lineSpacing = number('lineSpacingMM', 8);
          final writingSize = number('writingSize', 1);
          final penWeight = number('penWeight', 1);
          final profiles = Services.handwriting.profiles;
          final profileUid = note.rec.ref('profile');

          Widget stepper(String title, String key, double value, double min, double max, double step, String Function(double) label) =>
              ListTile(
                title: Text(title),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Weniger',
                    icon: const Icon(Icons.remove),
                    onPressed: value - step < min - 1e-9 ? null : () => put(key, value - step),
                  ),
                  SizedBox(width: 64, child: Text(label(value), textAlign: TextAlign.center)),
                  IconButton(
                    tooltip: 'Mehr',
                    icon: const Icon(Icons.add),
                    onPressed: value + step > max + 1e-9 ? null : () => put(key, value + step),
                  ),
                ]),
              );

          Widget percentSlider(String title, String key, double value, double min, double max) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [Expanded(child: Text(title)), Text('${(value * 100).round()} %')]),
                  Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: ((max - min) / 0.05).round(),
                    onChanged: (v) => put(key, (v * 20).round() / 20),
                  ),
                ]),
              );

          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Text('Papier & Stift', style: context.serifTitle, textAlign: TextAlign.center),
              const SectionTitle('Papier'),
              Group(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<PaperStyle>(
                    segments: [for (final p in PaperStyle.values) ButtonSegment(value: p, label: Text(p.title))],
                    selected: {paper},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => put('paper', s.first.name),
                  ),
                ),
                stepper('Zeilenabstand', 'lineSpacingMM', lineSpacing, 5, 14, 0.5, (v) => '${v.toStringAsFixed(1)} mm'),
                SwitchListTile(title: const Text('Korrekturrand'), value: flag('showMarginLine'), onChanged: (v) => put('showMarginLine', v)),
                SwitchListTile(title: const Text('Linien im PDF drucken'), value: flag('printPaper'), onChanged: (v) => put('printPaper', v)),
              ]),
              const SectionTitle('Schrift'),
              Group(children: [
                percentSlider('Schriftgröße', 'writingSize', writingSize, 0.7, 1.4),
                percentSlider('Stiftstärke', 'penWeight', penWeight, 0.6, 1.8),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 12, children: [
                    for (final color in PenColor.values)
                      Tooltip(
                        message: color.title,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => put('penColor', color.name),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: PageColors.pen(color),
                              shape: BoxShape.circle,
                              border: Border.all(color: color == pen ? context.colors.ink : Colors.transparent, width: 3),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
              const SectionTitle('Ränder'),
              Group(children: [
                for (final (title, key, fallback) in const [
                  ('Oben', 'marginTopMM', 20.0),
                  ('Unten', 'marginBottomMM', 15.0),
                  ('Links', 'marginLeftMM', 20.0),
                  ('Rechts', 'marginRightMM', 15.0),
                ])
                  stepper(title, key, number(key, fallback), 5, 45, 5, (v) => '${v.round()} mm'),
              ]),
              const SectionTitle('Seite'),
              Group(children: [
                SwitchListTile(title: const Text('Fach und Datum oben'), value: flag('showHeader'), onChanged: (v) => put('showHeader', v)),
                SwitchListTile(title: const Text('Seitenzahlen'), value: flag('showPageNumbers'), onChanged: (v) => put('showPageNumbers', v)),
              ]),
              const SectionTitle('Zuordnung'),
              Group(padding: const EdgeInsets.all(12), children: [
                SubjectField(
                  value: note.subject,
                  onChanged: (v) => store.update(note.rec, (data) {
                    data['subject'] = v;
                    data['topic'] = null;
                  }),
                ),
                if (note.subject != null)
                  DropdownButtonFormField<String?>(
                    initialValue: store.topicsOf(note.subject!).any((t) => t.uid == note.topic) ? note.topic : null,
                    decoration: const InputDecoration(labelText: 'Thema'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Kein Thema')),
                      for (final topic in store.topicsOf(note.subject!))
                        DropdownMenuItem<String?>(value: topic.uid, child: Text(topic.title)),
                    ],
                    onChanged: (v) => put('topic', v),
                  ),
                DropdownButtonFormField<String?>(
                  initialValue: store.exams.any((e) => e.uid == note.exam) ? note.exam : null,
                  decoration: const InputDecoration(labelText: 'Prüfung'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Keine Prüfung')),
                    for (final exam in store.exams)
                      DropdownMenuItem<String?>(
                        value: exam.uid,
                        child: Text('${store.examTitle(exam)} · ${Fmt.dayMonth(exam.date)}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => put('exam', v),
                ),
                TextFormField(
                  initialValue: note.folder,
                  decoration: const InputDecoration(labelText: 'Ordner'),
                  onChanged: (v) => put('folder', v.trim()),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Datum'),
                  trailing: Text(Fmt.numeric(note.noteDate)),
                  onTap: () async {
                    final day = await pickDay(context, note.noteDate);
                    if (day != null) put('noteDate', isoDate(day));
                  },
                ),
              ]),
              const SectionTitle('Handschrift'),
              Group(padding: const EdgeInsets.all(12), children: [
                DropdownButtonFormField<String?>(
                  initialValue: profiles.any((p) => p.uid == profileUid) ? profileUid : null,
                  decoration: const InputDecoration(labelText: 'Handschrift'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Standard')),
                    for (final HandwritingProfile p in profiles) DropdownMenuItem<String?>(value: p.uid, child: Text(p.displayName)),
                  ],
                  onChanged: (v) => put('profile', v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Der Text bleibt immer erhalten. Die Handschrift wird bei jeder Änderung neu gesetzt.',
                    style: TextStyle(color: context.colors.secondaryInk, fontSize: 13),
                  ),
                ),
              ]),
            ],
          );
        },
      );
}
