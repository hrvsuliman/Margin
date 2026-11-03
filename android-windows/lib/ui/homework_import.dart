import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../data/entities.dart';
import '../logic/homework_parser.dart';
import 'task_editor.dart';
import 'theme.dart';
import 'widgets.dart';

/// Photo of the board or homework book → text (on the device) → suggested task.
/// Android reads the photo with ML Kit; on Windows the text is pasted or typed.
Future<void> importHomework(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const HomeworkImport()));

class HomeworkImport extends StatefulWidget {
  const HomeworkImport({super.key});

  @override
  State<HomeworkImport> createState() => _HomeworkImportState();
}

class _HomeworkImportState extends State<HomeworkImport> {
  final _text = TextEditingController();
  bool _reading = false;
  String? _error;

  bool get _canRecognise => Platform.isAndroid;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _photo(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 90);
    if (file == null) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      _text.text = result.text;
      if (result.text.trim().isEmpty) _error = 'Auf dem Foto wurde kein Text erkannt. Näher ran und gerade halten.';
    } catch (error) {
      _error = 'Texterkennung fehlgeschlagen: $error';
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _reading = false);
    }
  }

  void _continue() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final suggestion = HomeworkParser.suggest(text, [for (final s in store.subjects) s.name]);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => TaskEditor(suggestion: suggestion)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Hausaufgabe erkennen'),
          actions: [TextButton(onPressed: _continue, child: const Text('Weiter'))],
        ),
        body: PageBody(maxWidth: 640, children: [
          const SizedBox(height: 8),
          Text(
            _canRecognise
                ? 'Fotografiere die Tafel oder dein Hausaufgabenheft. Der Text wird auf diesem Gerät erkannt – '
                    'nichts wird hochgeladen. Danach schlägt Margin Titel, Fach und Fälligkeit vor ("bis Freitag", "bis 12.11.", "morgen").'
                : 'Auf Windows kann Margin Fotos noch nicht lesen. Füge den Text der Hausaufgabe ein oder tippe ihn – '
                    'Margin schlägt dann Titel, Fach und Fälligkeit vor ("bis Freitag", "bis 12.11.", "morgen").',
            style: TextStyle(color: context.colors.secondaryInk),
          ),
          const SizedBox(height: 16),
          if (_canRecognise)
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _reading ? null : () => _photo(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Foto aufnehmen'),
              ),
              OutlinedButton.icon(
                onPressed: _reading ? null : () => _photo(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Foto auswählen'),
              ),
            ]),
          if (_reading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: context.colors.marginRed)),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Erkannter Text',
              hintText: 'Mathe: S. 34 Nr. 5a bis Freitag',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _continue, child: const Text('Als Aufgabe übernehmen')),
        ]),
      );
}
