import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/backup_import.dart';
import '../handwriting/analysis.dart';
import '../handwriting/handwriting_library.dart';
import '../handwriting/note_layout.dart';
import '../handwriting/page_painter.dart';
import 'theme.dart';
import 'widgets.dart';

/// Handwriting profiles on this device. They are written on the iPhone (pen and
/// paper) and come here through an iPhone backup file.
class HandwritingScreen extends StatelessWidget {
  const HandwritingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Handschrift')),
        body: ListenableBuilder(
          listenable: Services.handwriting,
          builder: (context, _) {
            final library = Services.handwriting;
            final profiles = library.profiles;
            final standard = library.defaultProfile?.uid;
            final secondary = TextStyle(color: context.colors.secondaryInk);
            return PageBody(maxWidth: 820, children: [
              const SizedBox(height: 8),
              Group(padding: const EdgeInsets.all(16), children: [
                Text(
                  'Deine Handschrift richtest du auf dem iPhone ein: Vorlage drucken, mit Stift ausfüllen, fotografieren. '
                  'Sichere dann dort ein Backup (Einstellungen › Backup sichern) oder nimm das automatische Backup '
                  'aus OneDrive/iCloud Drive – und lade die Datei hier.',
                  style: secondary,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Backup-Datei laden'),
                      onPressed: () => importBackup(context),
                    ),
                  ),
                ),
              ]),
              if (profiles.isEmpty)
                const EmptyState(
                  icon: Icons.draw_outlined,
                  title: 'Noch keine Handschrift',
                  message: 'Bis dahin erscheinen Notizen in Druckschrift.',
                )
              else ...[
                const SectionTitle('Profile'),
                for (final profile in profiles)
                  _ProfileCard(profile: profile, isDefault: profile.uid == standard),
              ],
            ]);
          },
        ),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.isDefault});
  final HandwritingProfile profile;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final library = Services.handwriting;
    final count = library.characterCount(profile.uid);
    final total = HandwritingCharset.all.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(['$count von $total Zeichen', if (isDefault) 'Standard'].join(' · ')),
            trailing: PopupMenuButton<String>(
              tooltip: 'Mehr',
              onSelected: (action) async {
                switch (action) {
                  case 'default':
                    library.setDefault(profile.uid);
                  case 'rename':
                    final name = await askText(context, 'Umbenennen', initial: profile.name, action: 'Sichern');
                    if (name != null && name.trim().isNotEmpty) library.rename(profile.uid, name.trim());
                  case 'delete':
                    final ok = await confirm(context, '„${profile.displayName}“ löschen?',
                        message: 'Nur auf diesem Gerät. Auf dem iPhone bleibt die Handschrift erhalten.');
                    if (ok) library.delete(profile.uid);
                }
              },
              itemBuilder: (_) => [
                if (!isDefault) const PopupMenuItem(value: 'default', child: Text('Als Standard')),
                const PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                const PopupMenuItem(value: 'delete', child: Text('Löschen')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: HandwritingPreview(profileUid: profile.uid, text: HandwritingCharset.pangram),
          ),
        ],
      ),
    );
  }
}

/// A few lines of text in a profile's handwriting on lined paper.
class HandwritingPreview extends StatelessWidget {
  const HandwritingPreview({super.key, required this.profileUid, required this.text, this.lines = 3});
  final String profileUid;
  final String text;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final spacing = PageSettings.mm(8);
    final settings = PageSettings(
      pageHeight: PageSettings.mm(6) + lines * spacing + PageSettings.mm(4),
      marginTop: PageSettings.mm(6),
      marginBottom: PageSettings.mm(4),
      marginLeft: PageSettings.mm(8),
      marginRight: PageSettings.mm(8),
      showMarginLine: false,
      showPageNumbers: false,
      showHeader: false,
    );
    final font = Services.handwriting.font(profileUid, settings.penRatio);
    final pages = NoteLayout.layout(NoteContent(title: '', header: '', body: text, seed: 7), settings, font);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: AspectRatio(
        aspectRatio: settings.pageWidth / settings.pageHeight,
        child: CustomPaint(painter: NotePagePainter(pages.isEmpty ? null : pages.first, settings)),
      ),
    );
  }
}

/// Lets the user pick an iPhone backup file and takes its handwriting (and
/// notes that aren't here yet).
Future<void> importBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'Margin-Backup', extensions: ['json'], mimeTypes: ['application/json']),
  ]);
  if (file == null) return;
  try {
    final backup = BackupImport.parse(await file.readAsString());
    final summary = BackupImport.apply(backup, store, Services.handwriting);
    final parts = [
      if (summary.profiles == 0) 'Im Backup ist keine Handschrift.'
      else '${summary.profiles == 1 ? '1 Handschrift' : '${summary.profiles} Handschriften'} mit ${summary.glyphs} Zeichenproben übernommen.',
      if (summary.notes > 0) '${summary.notes == 1 ? '1 Notiz' : '${summary.notes} Notizen'} hinzugefügt.',
      if (summary.skippedNotes > 0) '${summary.skippedNotes} schon vorhanden.',
    ];
    messenger.showSnackBar(SnackBar(content: Text(parts.join(' '))));
  } on FormatException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}
