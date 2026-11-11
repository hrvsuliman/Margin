import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/backup_import.dart';
import '../handwriting/analysis.dart';
import '../handwriting/handwriting_library.dart';
import '../handwriting/note_layout.dart';
import '../handwriting/page_painter.dart';
import 'handwriting_capture.dart';
import 'handwriting_profile.dart';
import 'theme.dart';
import 'widgets.dart';

/// Handwriting profiles on this device: written here with the pen, or taken
/// from an iPhone backup file.
class HandwritingScreen extends StatelessWidget {
  const HandwritingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Handschrift')),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Neue Handschrift'),
          onPressed: () => newProfile(context),
        ),
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
                  'Schreib jeden Buchstaben einmal mit dem Stift – Margin setzt deine Notizen dann in deiner Schrift. '
                  'Hast du deine Handschrift schon auf dem iPhone? Sichere dort ein Backup (Einstellungen › Backup sichern) '
                  'oder nimm das automatische Backup aus OneDrive/iCloud Drive – und lade die Datei hier. '
                  'Handschriftproben bleiben auf diesem Gerät.',
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
                EmptyState(
                  icon: Icons.draw_outlined,
                  title: 'Noch keine Handschrift',
                  message: 'Bis dahin erscheinen Notizen in Druckschrift.',
                  action: 'Mit dem Stift schreiben',
                  onAction: () => newProfile(context),
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileUid: profile.uid))),
            title: Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              '$count von $total Zeichen',
              '${library.sampleCount(profile.uid)} Proben',
              if (isDefault) 'Standard',
            ].join(' · ')),
            trailing: PopupMenuButton<String>(
              tooltip: 'Mehr',
              onSelected: (action) async {
                switch (action) {
                  case 'default':
                    library.setDefault(profile.uid);
                  case 'write':
                    await startCapture(context, profile.uid, CaptureSessions.missing(library, profile), title: 'Zeichen schreiben');
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
                const PopupMenuItem(value: 'write', child: Text('Zeichen schreiben')),
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

/// Creates a profile and starts writing its characters with the pen.
Future<void> newProfile(BuildContext context) async {
  final name = await askText(context, 'Neue Handschrift', hint: 'Name, z. B. „Meine Schrift“', action: 'Anlegen');
  if (name == null || !context.mounted) return;
  final library = Services.handwriting;
  final profile = library.createProfile(name.trim().isEmpty ? 'Meine Schrift' : name.trim());
  // The profile page, with the writing session on top of it.
  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileUid: profile.uid)));
  await startCapture(context, profile.uid, CaptureSessions.missing(library, profile), title: 'Zeichen schreiben');
}
