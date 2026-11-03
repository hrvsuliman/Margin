import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/entities.dart';
import '../data/store.dart';
import '../logic/pin_links.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens a note from a pin. Set by the notes feature (stage 2); null = read-only preview.
void Function(BuildContext context, String noteUid)? openNoteFromPin;

/// A cork board per subject: notes, videos, links, photos and sticky notes.
class Pinboard extends StatelessWidget {
  const Pinboard({super.key, required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final pins = store.pinsOf(subject.uid);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (pins.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Pinne Videos, Links, Fotos von der Tafel, Notizen oder Zettel an – alles für ${subject.name} an einem Ort.',
                style: TextStyle(color: context.colors.secondaryInk, fontSize: 13),
              ),
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              const spacing = 16.0;
              final columns = math.max(2, (constraints.maxWidth / 190).floor());
              final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Wrap(
                  spacing: spacing,
                  runSpacing: 20,
                  children: [
                    for (final pin in pins)
                      SizedBox(
                        width: width,
                        child: GestureDetector(
                          onTap: () => _open(context, pin),
                          onLongPress: () => _menu(context, pin, pins),
                          onSecondaryTap: () => _menu(context, pin, pins),
                          child: PinCard(pin: pin),
                        ),
                      ),
                  ],
                ),
              );
            }),
          Align(alignment: Alignment.centerLeft, child: _AddMenu(subject: subject, count: pins.length)),
        ]),
      ),
    );
  }

  Future<void> _open(BuildContext context, Pin pin) async {
    switch (pin.kind) {
      case 'sticky':
        await editPin(context, pin);
      case 'video' || 'link':
        final url = PinLinks.parse(pin.url);
        if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
      case 'photo':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoViewer(pin: pin)));
      case 'note':
        final note = pin.note;
        if (note == null) return;
        final open = openNoteFromPin;
        if (open != null) {
          open(context, note);
        } else {
          await _previewNote(context, note);
        }
    }
  }

  Future<void> _previewNote(BuildContext context, String noteUid) {
    final note = store.note(noteUid);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note?.displayTitle ?? 'Gelöschte Notiz'),
        content: SingleChildScrollView(child: Text(note?.body ?? '')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
      ),
    );
  }

  Future<void> _menu(BuildContext context, Pin pin, List<Pin> pins) async {
    final index = pins.indexWhere((p) => p.uid == pin.uid);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Bearbeiten'), onTap: () => Navigator.pop(context, 'edit')),
          if (index > 0)
            ListTile(leading: const Icon(Icons.arrow_back), title: const Text('Nach vorne'), onTap: () => Navigator.pop(context, 'up')),
          if (index < pins.length - 1)
            ListTile(leading: const Icon(Icons.arrow_forward), title: const Text('Nach hinten'), onTap: () => Navigator.pop(context, 'down')),
          if (pin.kind == 'video' || pin.kind == 'link')
            ListTile(leading: const Icon(Icons.copy), title: const Text('Link kopieren'), onTap: () => Navigator.pop(context, 'copy')),
          ListTile(
            leading: Icon(Icons.delete_outline, color: context.colors.marginRed),
            title: Text('Entfernen', style: TextStyle(color: context.colors.marginRed)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'edit':
        await editPin(context, pin);
      case 'up' || 'down':
        final other = pins[index + (action == 'up' ? -1 : 1)];
        final a = pin.sortIndex, b = other.sortIndex;
        store.update(pin.rec, (d) => d['sortIndex'] = a == b ? b + (action == 'up' ? -1 : 1) : b);
        store.update(other.rec, (d) => d['sortIndex'] = a);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: pin.url));
      case 'delete':
        store.delete(pin.rec);
    }
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.subject, required this.count});
  final Subject subject;
  final int count;

  Rec _insert(String kind, Map<String, dynamic> fields) {
    final pins = store.pinsOf(subject.uid);
    final last = pins.isEmpty ? -1 : pins.map((p) => p.sortIndex).reduce(math.max);
    return store.add(Kind.pin, {
      'subject': subject.uid,
      'kind': kind,
      'sortIndex': last + 1,
      'color': kind == 'sticky' ? const ['mustard', 'green', 'blue', 'coral'][count % 4] : subject.colorKey,
      ...fields,
    });
  }

  Future<void> _addLink(BuildContext context) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final initial = PinLinks.parse(clip?.text ?? '') != null ? clip!.text!.trim() : '';
    if (!context.mounted) return;
    final raw = await askText(context, 'Video oder Link anheften', initial: initial, hint: 'https://…', action: 'Anheften');
    final url = PinLinks.parse(raw ?? '');
    if (url == null) return;
    final video = PinLinks.youTubeId(url) != null || PinLinks.isVideoHost(url);
    final rec = _insert(video ? 'video' : 'link', {'url': url.toString(), 'title': ''});
    final title = await PinLinks.title(url);
    if (title != null && store.byUid(rec.uid) != null && rec.str('title').isEmpty) {
      store.update(rec, (d) => d['title'] = title);
    }
  }

  Future<void> _addPhoto(BuildContext context, ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 90);
    if (file == null) return;
    try {
      final photo = await compressPhoto(await file.readAsBytes());
      _insert('photo', {'photo': photo, 'title': ''});
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Foto konnte nicht übernommen werden: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Anheften',
        onSelected: (choice) async {
          switch (choice) {
            case 'sticky':
              final rec = _insert('sticky', {'text': ''});
              await editPin(context, Pin(rec), isNew: true);
            case 'link':
              await _addLink(context);
            case 'camera':
              await _addPhoto(context, ImageSource.camera);
            case 'gallery':
              await _addPhoto(context, ImageSource.gallery);
            case 'note':
              final note = store.add(Kind.note, {'subject': subject.uid});
              _insert('note', {'note': note.uid});
              if (context.mounted) openNoteFromPin?.call(context, note.uid);
            default:
              if (choice.startsWith('note:')) _insert('note', {'note': choice.substring(5)});
          }
        },
        itemBuilder: (context) {
          final notes = store.notes.where((n) => n.subject == subject.uid).take(15).toList();
          return [
            const PopupMenuItem(value: 'sticky', child: ListTile(leading: Icon(Icons.sticky_note_2_outlined), title: Text('Zettel'))),
            const PopupMenuItem(value: 'link', child: ListTile(leading: Icon(Icons.smart_display_outlined), title: Text('Video oder Link'))),
            if (Platform.isAndroid)
              const PopupMenuItem(value: 'camera', child: ListTile(leading: Icon(Icons.photo_camera_outlined), title: Text('Foto aufnehmen'))),
            const PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_outlined), title: Text('Foto auswählen'))),
            if (openNoteFromPin != null)
              const PopupMenuItem(value: 'note', child: ListTile(leading: Icon(Icons.note_add_outlined), title: Text('Neue Notiz'))),
            for (final n in notes)
              PopupMenuItem(value: 'note:${n.uid}', child: ListTile(leading: const Icon(Icons.description_outlined), title: Text(n.displayTitle))),
          ];
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.push_pin_outlined, color: context.colors.marginRed, size: 20),
            const SizedBox(width: 8),
            Text('Anheften', style: TextStyle(color: context.colors.marginRed, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

final _photoCache = <String, Uint8List>{};

Uint8List? pinPhoto(Pin pin) {
  final data = pin.photo;
  if (data == null) return null;
  final key = '${pin.uid}:${pin.rec.updatedAt}';
  return _photoCache[key] ??= () {
    try {
      return base64Decode(data);
    } catch (_) {
      return Uint8List(0);
    }
  }();
}

/// One pinned item, slightly tilted, with a red pin on top.
class PinCard extends StatelessWidget {
  const PinCard({super.key, required this.pin});
  final Pin pin;

  double get _tilt {
    var hash = 0;
    for (final unit in pin.uid.codeUnits) {
      hash = (hash * 31 + unit) & 0xFFFF;
    }
    return (hash % 7 - 3) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: _tilt,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            constraints: const BoxConstraints(minHeight: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(4), child: _content(context)),
          ),
          Positioned(
            top: -5,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: context.colors.marginRed,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 1, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _content(BuildContext context) {
    final color = subjectColor(context, pin.color);
    final c = context.colors;
    switch (pin.kind) {
      case 'sticky':
        return Container(
          constraints: const BoxConstraints(minHeight: 120),
          width: double.infinity,
          color: Color.alphaBlend(color.withValues(alpha: 0.35), Colors.white),
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
          child: Text(
            pin.text.isEmpty ? 'Tippen zum Schreiben' : pin.text,
            style: TextStyle(
              fontFamily: serifFamily,
              fontFamilyFallback: serifFallback,
              fontSize: 15,
              color: pin.text.isEmpty ? Colors.black38 : Colors.black.withValues(alpha: 0.8),
            ),
          ),
        );
      case 'photo':
        final bytes = pinPhoto(pin);
        if (bytes == null || bytes.isEmpty) return _missing(context);
        return Stack(children: [
          Image.memory(bytes, height: 130, width: double.infinity, fit: BoxFit.cover, gaplessPlayback: true),
          if (pin.title.isNotEmpty)
            Positioned(
              left: 6,
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4)),
                child: Text(pin.title, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ]);
      case 'video':
        final url = PinLinks.parse(pin.url);
        final id = url == null ? null : PinLinks.youTubeId(url);
        return Container(
          color: c.sheet,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 86,
              child: Stack(fit: StackFit.expand, children: [
                Container(color: Colors.black.withValues(alpha: 0.85)),
                if (id != null)
                  Image.network(
                    PinLinks.thumbnail(id),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                Center(child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white.withValues(alpha: 0.92))),
              ]),
            ),
            _titleBlock(context, url),
          ]),
        );
      case 'link':
        final url = PinLinks.parse(pin.url);
        return Container(
          color: c.sheet,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.link, color: color)),
            _titleBlock(context, url),
          ]),
        );
      default:
        final note = store.note(pin.note);
        return Container(
          color: c.sheet,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 86,
              color: c.paper,
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
              child: Text(
                note?.body ?? '',
                maxLines: 4,
                overflow: TextOverflow.fade,
                style: TextStyle(fontSize: 10, color: penColor(note?.penColor ?? 'royalBlue', dark: context.isDark)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                note?.displayTitle ?? 'Gelöschte Notiz',
                maxLines: 2,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
          ]),
        );
    }
  }

  Widget _titleBlock(BuildContext context, Uri? url) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            pin.title.isNotEmpty ? pin.title : (url?.host ?? 'Link'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.ink),
          ),
          if (pin.text.isNotEmpty)
            Text(pin.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.colors.secondaryInk)),
        ]),
      );

  Widget _missing(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 120),
        color: context.colors.sheet,
        alignment: Alignment.center,
        child: Text('Foto fehlt', style: TextStyle(color: context.colors.secondaryInk, fontSize: 12)),
      );
}

/// Edit a sticky note, or the title and comment of a link, video or photo.
Future<void> editPin(BuildContext context, Pin pin, {bool isNew = false}) async {
  final sticky = pin.kind == 'sticky';
  final title = TextEditingController(text: pin.title);
  final text = TextEditingController(text: pin.text);
  var color = pin.color;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(sticky ? 'Zettel' : pinKinds[pin.kind]!, style: context.serifTitle),
          const SizedBox(height: 14),
          if (!sticky) ...[
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: text,
            autofocus: sticky,
            minLines: sticky ? 4 : 2,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: sticky ? 'Text' : 'Kommentar', alignLabelWithHint: true),
          ),
          if (sticky) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 10, children: [
              for (final key in const ['mustard', 'green', 'blue', 'coral', 'pink', 'violet', 'gray'])
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => color = key),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: subjectColor(context, key),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == key ? context.colors.ink : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fertig')),
        ]),
      ),
    ),
  );
  if (store.byUid(pin.uid) == null) return;
  if (saved == true) {
    store.update(pin.rec, (d) {
      d['title'] = title.text.trim();
      d['text'] = text.text.trim();
      d['color'] = color;
    });
  } else if (isNew && sticky && pin.text.isEmpty) {
    store.delete(pin.rec);
  }
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.pin});
  final Pin pin;

  @override
  Widget build(BuildContext context) {
    final bytes = pinPhoto(pin);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(pin.title, style: const TextStyle(color: Colors.white)),
      ),
      body: bytes == null || bytes.isEmpty
          ? const SizedBox.shrink()
          : InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(bytes))),
    );
  }
}
