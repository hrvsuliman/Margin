import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/store.dart';
import 'sync_crypto.dart';

/// Keeps this device and the user's own sync server in step (docs/SYNC.md, section 4).
/// Off until the user turns it on in Einstellungen › Abgleich.
class SyncClient extends ChangeNotifier {
  SyncClient(this.store, this.configFile, {http.Client? client}) : _http = client ?? http.Client();

  final Store store;
  final File? configFile;
  final http.Client _http;

  SyncConfig? config;
  bool syncing = false;
  DateTime? lastSync;
  String? lastError;

  /// Records on the server this device could not decrypt (other passphrase or damaged).
  int unreadable = 0;

  /// Set when the device clock is more than two minutes away from the server's.
  Duration? clockSkew;

  Timer? _debounce;
  Timer? _periodic;

  bool get enabled => config != null;

  List<Rec> get problems => store.allRecords.where((r) => r.problem != null).toList();
  int get pending => store.allRecords.where((r) => r.dirty && r.problem == null).length;

  Future<void> load() async {
    final file = configFile;
    if (file != null && await file.exists()) {
      try {
        config = SyncConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        config = null;
      }
    }
    store.onLocalChange = _scheduleSoon;
    if (enabled) _start();
  }

  /// Checks the server, stores the keys and uploads everything once.
  Future<void> enable({required String server, required SyncKeys keys}) async {
    final base = normalizeServer(server);
    final candidate = SyncConfig(server: base, vault: keys.vault, key: keys.key);
    final response = await _http
        .get(Uri.parse('$base/e2e/info'), headers: candidate.headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404 || response.statusCode == 401) {
      throw const SyncException('Der Server kennt den Abgleich nicht. Ist der Connector auf dem neuesten Stand (npx wrangler deploy)?');
    }
    if (response.statusCode != 200) throw SyncException('Server antwortet mit ${response.statusCode}.');
    config = candidate;
    await _saveConfig();
    // A new vault starts from the beginning: everything here goes up, everything there comes down.
    store.cursor = 0;
    for (final rec in store.allRecords) {
      rec.dirty = true;
      rec.problem = null;
    }
    store.syncChanged();
    _start();
    await syncNow();
  }

  /// Stops syncing. The data on this device stays; the server copy is not deleted.
  Future<void> disable() async {
    config = null;
    _periodic?.cancel();
    _debounce?.cancel();
    lastSync = null;
    lastError = null;
    final file = configFile;
    if (file != null && await file.exists()) await file.delete();
    notifyListeners();
  }

  void _start() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    _scheduleSoon();
  }

  void _scheduleSoon() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  Future<void> syncNow() async {
    final cfg = config;
    if (cfg == null || syncing) return;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await _push(cfg);
      await _pull(cfg);
      lastSync = DateTime.now();
    } on SyncException catch (error) {
      lastError = error.message;
    } on TimeoutException {
      lastError = 'Server antwortet nicht. Später nochmal.';
    } on SocketException {
      lastError = 'Keine Verbindung zum Server.';
    } on http.ClientException {
      lastError = 'Keine Verbindung zum Server.';
    } catch (error) {
      lastError = 'Abgleich fehlgeschlagen: $error';
    } finally {
      syncing = false;
      store.syncChanged();
      notifyListeners();
    }
  }

  Future<void> _push(SyncConfig cfg) async {
    final dirty = store.allRecords.where((r) => r.dirty && r.problem == null).toList();
    var index = 0;
    while (index < dirty.length) {
      // Batches of at most 200 records and about 6 MB.
      final batch = <Map<String, dynamic>>[];
      final sent = <String, int>{};
      var size = 0;
      while (index < dirty.length && batch.length < 200 && size < 6000000) {
        final rec = dirty[index++];
        final blob = await SyncCrypto.seal(cfg.key, rec.uid, rec.updatedAt, {
          'type': rec.type,
          'deleted': rec.deleted,
          'data': rec.data,
        });
        if (blob.length > 1900000) {
          rec.problem = 'tooLarge';
          continue;
        }
        size += blob.length;
        sent[rec.uid] = rec.updatedAt;
        batch.add({'uid': rec.uid, 'updatedAt': rec.updatedAt, 'blob': blob});
      }
      if (batch.isEmpty) continue;
      final response = await _http
          .post(Uri.parse('${cfg.server}/e2e/push'), headers: cfg.headers, body: jsonEncode({'records': batch}))
          .timeout(const Duration(seconds: 60));
      _checkClock(response);
      if (response.statusCode != 200) throw SyncException('Hochladen fehlgeschlagen (${response.statusCode}).');
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      for (final uid in (result['accepted'] as List? ?? const []).cast<String>()) {
        final rec = store.raw(uid);
        // Only if it didn't change again while uploading.
        if (rec != null && rec.updatedAt == sent[uid]) rec.dirty = false;
      }
      for (final item in (result['rejected'] as List? ?? const []).cast<Map>()) {
        final rec = store.raw(item['uid'] as String);
        final reason = item['reason'];
        // "stale": the server has a newer version; the pull below brings it.
        if (rec != null && reason != 'stale') rec.problem = reason as String?;
      }
    }
  }

  Future<void> _pull(SyncConfig cfg) async {
    var more = true;
    var unreadableNow = 0;
    while (more) {
      final response = await _http
          .get(Uri.parse('${cfg.server}/e2e/pull?since=${store.cursor}'), headers: cfg.headers)
          .timeout(const Duration(seconds: 60));
      _checkClock(response);
      if (response.statusCode != 200) throw SyncException('Abrufen fehlgeschlagen (${response.statusCode}).');
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in (result['records'] as List? ?? const []).cast<Map>()) {
        final uid = item['uid'] as String;
        final updatedAt = (item['updatedAt'] as num).toInt();
        final local = store.raw(uid);
        if (local != null && local.updatedAt >= updatedAt) continue;
        try {
          final payload = await SyncCrypto.open(cfg.key, uid, updatedAt, item['blob'] as String);
          store.applyRemote(
            uid: uid,
            updatedAt: updatedAt,
            type: payload['type'] as String,
            deleted: payload['deleted'] == true,
            data: Map<String, dynamic>.from(payload['data'] as Map? ?? {}),
          );
        } catch (_) {
          unreadableNow += 1;
        }
      }
      store.cursor = (result['cursor'] as num?)?.toInt() ?? store.cursor;
      more = result['more'] == true;
    }
    unreadable = unreadableNow;
  }

  void _checkClock(http.Response response) {
    final header = response.headers['date'];
    if (header == null) return;
    try {
      final server = HttpDate.parse(header);
      final skew = DateTime.now().difference(server);
      clockSkew = skew.inSeconds.abs() > 120 ? skew : null;
    } catch (_) {}
  }

  Future<void> _saveConfig() async {
    final file = configFile;
    final cfg = config;
    if (file == null || cfg == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(cfg.toJson()), flush: true);
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  /// "margin-connector.name.workers.dev/" → "https://margin-connector.name.workers.dev"
  static String normalizeServer(String raw) {
    var server = raw.trim();
    if (!server.startsWith('http://') && !server.startsWith('https://')) server = 'https://$server';
    final uri = Uri.parse(server);
    return '${uri.scheme}://${uri.authority}';
  }

  /// Six words and a number, about 55 bits – long enough against guessing.
  static String suggestPassphrase() {
    final random = Random.secure();
    final words = List.generate(6, (_) => _words[random.nextInt(_words.length)]);
    return '${words.join(' ')} ${10 + random.nextInt(90)}';
  }

  /// At least four words or sixteen characters.
  static bool strongEnough(String passphrase) {
    final text = passphrase.trim();
    final words = text.split(RegExp(r'\s+')).length;
    return (text.length >= 16 && words >= 4) || text.length >= 24;
  }

  static const _words = [
    'apfel', 'ampel', 'anker', 'atlas', 'auto', 'bach', 'bahn', 'ball', 'band', 'bank', 'bart', 'baum', 'becher',
    'berg', 'besen', 'biene', 'birne', 'blatt', 'blitz', 'blume', 'boot', 'brief', 'brille', 'brot', 'brunnen',
    'buch', 'burg', 'butter', 'dach', 'dampf', 'decke', 'deich', 'dose', 'drache', 'draht', 'dschungel', 'duft',
    'eiche', 'eimer', 'eis', 'elch', 'ente', 'erbse', 'esel', 'eule', 'fabrik', 'faden', 'fahne', 'falke', 'farbe',
    'feder', 'fee', 'feld', 'fels', 'fenster', 'feuer', 'fisch', 'flagge', 'flasche', 'floh', 'flur', 'fluss',
    'fohlen', 'frosch', 'fuchs', 'gabel', 'garten', 'geige', 'geld', 'gras', 'gurke', 'hafen', 'hagel', 'hahn',
    'hammer', 'hand', 'harfe', 'hase', 'haus', 'hecke', 'heft', 'helm', 'hemd', 'herd', 'himmel', 'hirsch',
    'hobel', 'honig', 'horn', 'hose', 'hut', 'igel', 'insel', 'jacke', 'jagd', 'kabel', 'kaffee', 'kakao', 'kamel',
    'kamm', 'kanal', 'kanne', 'karte', 'kasse', 'katze', 'kegel', 'keks', 'kerze', 'kette', 'kino', 'kirsche',
    'kiste', 'klee', 'knopf', 'koch', 'koffer', 'komet', 'korb', 'kran', 'kranich', 'kreide', 'krone', 'kuchen',
    'kugel', 'lampe', 'land', 'laterne', 'laub', 'leiter', 'licht', 'linde', 'lineal', 'loch', 'lupe', 'magnet',
    'mantel', 'markt', 'maus', 'meer', 'mehl', 'messer', 'milch', 'mond', 'moos', 'motor', 'mühle', 'muschel',
    'nadel', 'nagel', 'nebel', 'nest', 'netz', 'nuss', 'ofen', 'ohr', 'orgel', 'palme', 'papier', 'park', 'pfad',
    'pferd', 'pflaume', 'pilz', 'pinsel', 'planet', 'platz', 'pokal', 'post', 'puppe', 'quelle', 'rabe', 'rad',
    'rakete', 'regen', 'reh', 'reifen', 'ring', 'rock', 'rose', 'rucksack', 'sack', 'salz', 'sand', 'schaf',
    'schal', 'schiff', 'schild', 'schloss', 'schnee', 'schuh', 'see', 'segel', 'seil', 'sessel', 'sieb', 'socke',
    'sofa', 'sonne', 'spiegel', 'stadt', 'stein', 'stern', 'stiefel', 'strand', 'strom', 'stuhl', 'sturm', 'suppe',
    'tafel', 'tanne', 'tasche', 'tasse', 'teich', 'teller', 'tiger', 'tisch', 'topf', 'traube', 'trommel', 'tulpe',
    'turm', 'uhr', 'ufer', 'vase', 'vogel', 'vulkan', 'waage', 'wagen', 'wald', 'wal', 'wand', 'wasser', 'welle',
    'wiese', 'wind', 'wolke', 'wolle', 'wurm', 'wurzel', 'zahn', 'zaun', 'zebra', 'zelt', 'ziege', 'zimmer', 'zitrone',
    'zucker', 'zug', 'zwerg', 'zwiebel',
  ];
}

class SyncConfig {
  SyncConfig({required this.server, required this.vault, required this.key});

  final String server;
  final String vault;
  final List<int> key;

  Map<String, String> get headers => {'Authorization': 'Bearer $vault', 'Content-Type': 'application/json'};

  Map<String, dynamic> toJson() => {'server': server, 'vault': vault, 'key': base64.encode(key)};

  factory SyncConfig.fromJson(Map<String, dynamic> json) => SyncConfig(
        server: json['server'] as String,
        vault: json['vault'] as String,
        key: base64.decode(json['key'] as String),
      );
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}
