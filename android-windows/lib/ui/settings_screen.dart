import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/dates.dart';
import '../sync/sync_client.dart';
import '../sync/sync_crypto.dart';
import 'handwriting_screen.dart';
import 'theme.dart';
import 'widgets.dart';

const appVersion = '0.2.0';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Einstellungen')),
        body: ListenableBuilder(
          listenable: Listenable.merge([Services.sync, Services.store, Services.handwriting]),
          builder: (context, _) {
            final sync = Services.sync;
            final secondary = TextStyle(color: context.colors.secondaryInk);
            return PageBody(maxWidth: 640, children: [
              const SectionTitle('Abgleich'),
              if (!sync.enabled)
                Group(children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('Aus'),
                    subtitle: const Text('Alles bleibt auf diesem Gerät.'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Abgleich einrichten'),
                    subtitle: const Text('iPhone, Android und PC mit denselben Daten – verschlüsselt über deinen eigenen Server.'),
                    trailing: Icon(Icons.chevron_right, color: context.colors.faintInk),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncSetup())),
                  ),
                ])
              else
                Group(children: [
                  ListTile(
                    leading: Icon(sync.lastError == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                    title: Text(sync.syncing
                        ? 'Gleiche ab …'
                        : sync.lastError ?? (sync.lastSync == null ? 'Eingeschaltet' : 'Abgeglichen um ${Fmt.time(sync.lastSync!)}')),
                    subtitle: Text(sync.config!.server.replaceFirst('https://', '')),
                  ),
                  if (sync.pending > 0)
                    ListTile(leading: const Icon(Icons.upload_outlined), title: Text('${sync.pending} Änderungen warten aufs Hochladen')),
                  if (sync.problems.isNotEmpty)
                    ListTile(
                      leading: Icon(Icons.warning_amber_outlined, color: context.colors.marginRed),
                      title: Text('${sync.problems.length} Einträge zu groß zum Abgleichen'),
                      subtitle: const Text('Meist Fotos oder sehr viel Stift-Tinte. Sie bleiben auf diesem Gerät.'),
                    ),
                  if (sync.unreadable > 0)
                    ListTile(
                      leading: Icon(Icons.lock_outline, color: context.colors.marginRed),
                      title: Text('${sync.unreadable} Einträge konnten nicht gelesen werden'),
                      subtitle: const Text('Sie wurden mit einer anderen Passphrase verschlüsselt oder sind beschädigt.'),
                    ),
                  if (sync.clockSkew != null)
                    ListTile(
                      leading: Icon(Icons.schedule, color: context.colors.marginRed),
                      title: const Text('Die Uhr dieses Geräts geht falsch'),
                      subtitle: Text(
                        'Abweichung ${sync.clockSkew!.inMinutes.abs()} Min. Beim Abgleich gewinnt die neueste Änderung – '
                        'stell die Uhrzeit auf automatisch, sonst können Änderungen verloren gehen.',
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Jetzt abgleichen'),
                    enabled: !sync.syncing,
                    onTap: sync.syncNow,
                  ),
                  ListTile(
                    leading: Icon(Icons.power_settings_new, color: context.colors.marginRed),
                    title: Text('Abgleich ausschalten', style: TextStyle(color: context.colors.marginRed)),
                    subtitle: const Text('Die Daten auf diesem Gerät bleiben. Die verschlüsselte Kopie auf dem Server auch.'),
                    onTap: () async {
                      if (await confirm(context, 'Abgleich ausschalten?', action: 'Ausschalten')) await sync.disable();
                    },
                  ),
                ]),
              const SectionTitle('Handschrift'),
              Group(children: [
                ListTile(
                  leading: const Icon(Icons.draw_outlined),
                  title: const Text('Handschrift'),
                  subtitle: Text(
                    Services.handwriting.profiles.isEmpty
                        ? 'Noch keine – aus einem iPhone-Backup laden'
                        : Services.handwriting.profiles.map((p) => p.displayName).join(', '),
                  ),
                  trailing: Icon(Icons.chevron_right, color: context.colors.faintInk),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HandwritingScreen())),
                ),
              ]),
              const SectionTitle('Daten'),
              Group(children: [
                FutureBuilder<Directory>(
                  future: getApplicationSupportDirectory(),
                  builder: (context, snapshot) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Gespeichert auf diesem Gerät'),
                    subtitle: Text(snapshot.data?.path ?? '…'),
                    onLongPress: snapshot.data == null ? null : () => Clipboard.setData(ClipboardData(text: snapshot.data!.path)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dataset_outlined),
                  title: Text('${Services.store.allRecords.where((r) => !r.deleted).length} Einträge'),
                ),
              ]),
              const SectionTitle('Über'),
              Group(children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text('Margin $appVersion für ${Platform.isWindows ? 'Windows' : 'Android'}'),
                  subtitle: Text(
                    'Fächer mit Pinnwand, Aufgaben, Hausaufgaben-Foto, Prüfungen, Notizen in deiner Handschrift mit PDF. '
                    'Kalender, Karteikarten und Fokus-Timer folgen in den nächsten Stufen.',
                    style: secondary,
                  ),
                ),
              ]),
            ]);
          },
        ),
      );
}

/// Explains what syncing does, then sets it up with the server address and a passphrase.
class SyncSetup extends StatefulWidget {
  const SyncSetup({super.key});

  @override
  State<SyncSetup> createState() => _SyncSetupState();
}

class _SyncSetupState extends State<SyncSetup> {
  final _server = TextEditingController();
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();
  bool _hidden = true;
  bool _noted = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _fail(String message) => setState(() => _error = message);

  Future<void> _start() async {
    final passphrase = _passphrase.text;
    setState(() => _error = null);
    if (_server.text.trim().isEmpty) return _fail('Bitte die Adresse deines Servers eintragen.');
    if (!SyncClient.strongEnough(passphrase)) {
      return _fail('Die Passphrase ist zu kurz: mindestens 4 Wörter und 16 Zeichen.');
    }
    if (passphrase.trim() != _repeat.text.trim()) return _fail('Die beiden Passphrasen sind nicht gleich.');
    setState(() => _working = true);
    try {
      final keys = await SyncCrypto.deriveKeys(passphrase);
      await Services.sync.enable(server: _server.text, keys: keys);
      if (mounted) Navigator.pop(context);
    } on SyncException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Der Server ist nicht erreichbar. Stimmt die Adresse? ($error)');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(color: context.colors.secondaryInk, height: 1.4);
    return Scaffold(
      appBar: AppBar(title: const Text('Abgleich einrichten')),
      body: PageBody(maxWidth: 640, children: [
        const SectionTitle('So funktioniert es'),
        Text(
          'Margin schickt deine Fächer, Aufgaben, Prüfungen, Stunden, Notizen, Pinnwände und Karteikarten an deinen eigenen '
          'Server (den Margin-Connector auf deinem Cloudflare-Konto). Jeder Eintrag wird vorher auf diesem Gerät mit deiner '
          'Passphrase verschlüsselt (AES-256). Der Server – und auch Cloudflare – sieht nur unlesbare Daten.',
          style: secondary,
        ),
        const SizedBox(height: 10),
        Text(
          'Auf jedem Gerät gibst du dieselbe Serveradresse und dieselbe Passphrase ein. Die Passphrase wird nirgends '
          'gespeichert oder verschickt. Vergisst du sie, kann niemand die Daten auf dem Server wiederherstellen – '
          'die Daten auf deinen Geräten bleiben aber erhalten.',
          style: secondary,
        ),
        const SizedBox(height: 10),
        Text(
          'Bei Änderungen am selben Eintrag auf zwei Geräten gewinnt die neueste. Fotos von Pinnwänden werden mit abgeglichen; '
          'Dateianhänge, Handschrift-Profile und Aufnahmen bleiben auf dem Gerät. Das iPhone kann noch nicht mitmachen – '
          'das kommt mit einem iPhone-Update.',
          style: secondary,
        ),
        const SectionTitle('Server'),
        TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Adresse', hintText: 'margin-connector.DEINNAME.workers.dev'),
        ),
        const SectionTitle('Passphrase'),
        TextField(
          controller: _passphrase,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Passphrase',
            helperText: 'Mindestens 4 Wörter. Am besten nur a–z, Zahlen und Leerzeichen.',
            suffixIcon: IconButton(
              tooltip: _hidden ? 'Zeigen' : 'Verbergen',
              icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Passphrase vorschlagen (für das erste Gerät)'),
            onPressed: () => setState(() {
              _passphrase.text = SyncClient.suggestPassphrase();
              _repeat.clear();
              _hidden = false;
            }),
          ),
        ),
        TextField(
          controller: _repeat,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Passphrase wiederholen'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _noted,
          onChanged: (v) => setState(() => _noted = v == true),
          title: const Text('Ich habe die Passphrase aufgeschrieben (Papier oder Passwort-Manager).'),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: context.colors.marginRed))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _working || !_noted ? null : _start,
          child: _working
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Schlüssel wird berechnet …'),
                ])
              : const Text('Verschlüsselt abgleichen'),
        ),
      ]),
    );
  }
}
