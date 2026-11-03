import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:margin/data/entities.dart';
import 'package:margin/data/store.dart';
import 'package:margin/sync/sync_client.dart';
import 'package:margin/sync/sync_crypto.dart';

// Same vectors as connector/test.mjs and docs/SYNC.md.
const vectorKey = '5314c46262f08cedf6afdcada238475fa37dab724ff206447c0af0298d91bcca';
const vectorVault = 'eb4bb41576e9e67496a94611417ced57ac85c8bca9acee6324ef625b01b9d55d';
const vectorUid = '8D0B9F5E-2B7C-4C1A-9E3F-1A2B3C4D5E6F';
const vectorBlob =
    'AAECAwQFBgcICQoLgqL/ULm19SQ4qQ4ZIiRuTzyqKi6QXSp/6G3JfKhLQZzMSSL1yj4uClzgkjDoqLGuA9uXosmWg7Q24zfCl9Rc3HEsDCt22BmKn7HVXA+Odp6f7xom4YdfmA6gwER4MdxXbeMbdXKLWW8jQ3Pn8mIaAGFBSwLcatom4r5VSHT9C9lk';

Uint8List fromHex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

/// The Worker's sync endpoints, in memory (same rules as connector/worker.js).
class FakeServer {
  final records = <String, Map<String, dynamic>>{};
  var seq = 0;

  MockClient get client => MockClient((request) async {
        if (request.headers['Authorization'] != 'Bearer $vectorVault') return http.Response('{}', 401);
        final path = request.url.path;
        if (path == '/e2e/info') return _json({'records': records.length, 'cursor': seq});
        if (path == '/e2e/push') {
          final incoming = (jsonDecode(request.body) as Map)['records'] as List;
          final accepted = <String>[];
          final rejected = <Map<String, dynamic>>[];
          for (final r in incoming.cast<Map>()) {
            final current = records[r['uid']];
            if (current != null && (current['updatedAt'] as int) >= (r['updatedAt'] as int)) {
              rejected.add({'uid': r['uid'], 'reason': 'stale', 'updatedAt': current['updatedAt']});
              continue;
            }
            seq += 1;
            records[r['uid'] as String] = {...Map<String, dynamic>.from(r), 'seq': seq};
            accepted.add(r['uid'] as String);
          }
          return _json({'accepted': accepted, 'rejected': rejected, 'cursor': seq});
        }
        if (path == '/e2e/pull') {
          final since = int.parse(request.url.queryParameters['since'] ?? '0');
          final changed = records.values.where((r) => (r['seq'] as int) > since).toList()
            ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
          return _json({'records': changed, 'cursor': seq, 'more': false});
        }
        return http.Response('{}', 404);
      });

  static http.Response _json(Object value) =>
      http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'});
}

void main() {
  test('key derivation matches the reference implementation', () async {
    final keys = await SyncCrypto.deriveKeys('  korrekt pferd batterie heftklammer ');
    expect(SyncCrypto.hex(keys.key), vectorKey);
    expect(keys.vault, vectorVault);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('records encrypt to the same bytes as in Node and open again', () async {
    final key = fromHex(vectorKey);
    final payload = {
      'type': 'task',
      'deleted': false,
      'data': {'uid': vectorUid, 'title': 'S. 42 Nr. 3'},
    };
    final blob = await SyncCrypto.seal(key, vectorUid, 1762160400000, payload, nonce: List.generate(12, (i) => i));
    expect(blob, vectorBlob);
    final opened = await SyncCrypto.open(key, vectorUid, 1762160400000, vectorBlob);
    expect(opened['type'], 'task');
    expect((opened['data'] as Map)['title'], 'S. 42 Nr. 3');
    // uid and timestamp are bound to the ciphertext.
    expect(() => SyncCrypto.open(key, vectorUid, 1762160400001, vectorBlob), throwsA(anything));
    expect(() => SyncCrypto.open(key, 'OTHER', 1762160400000, vectorBlob), throwsA(anything));
  });

  test('two devices end up with the same data, last write wins', () async {
    final server = FakeServer();
    final keys = SyncKeys(fromHex(vectorKey), vectorVault);
    final phone = Store();
    final pc = Store();
    final phoneSync = SyncClient(phone, null, client: server.client);
    final pcSync = SyncClient(pc, null, client: server.client);
    addTearDown(() {
      phone.onLocalChange = pc.onLocalChange = null;
      phoneSync.dispose();
      pcSync.dispose();
    });

    final subject = phone.add(Kind.subject, {'name': 'Mathematik', 'colorKey': 'blue'});
    final task = phone.add(Kind.task, {'title': 'S. 42 Nr. 3', 'subject': subject.uid});
    await phoneSync.enable(server: 'margin.example.workers.dev', keys: keys);
    expect(phoneSync.lastError, isNull);
    expect(phoneSync.pending, 0);
    expect(server.records.values.map((r) => r['blob'] as String).join(), isNot(contains('Mathematik')));

    await pcSync.enable(server: 'https://margin.example.workers.dev/', keys: keys);
    expect(pc.subjects.single.name, 'Mathematik');
    expect(pc.tasks.single.subject, subject.uid);
    // Swift needs every DTO field; defaults travel along.
    expect(pc.tasks.single.rec.data['hasDueTime'], false);

    // Edit on the PC, delete the subject on the phone.
    pc.update(pc.tasks.single.rec, (d) => d['title'] = 'S. 42 Nr. 3 und 4');
    await pcSync.syncNow();
    phone.delete(subject);
    await phoneSync.syncNow();
    await pcSync.syncNow();
    expect(Task(phone.byUid(task.uid)!).title, 'S. 42 Nr. 3 und 4');
    expect(pc.subjects, isEmpty);

    // A stale local edit loses against a newer one from the server.
    final pcTask = pc.byUid(task.uid)!;
    phone.update(phone.byUid(task.uid)!, (d) => d['title'] = 'neu vom Handy');
    await phoneSync.syncNow();
    pc.update(pcTask, (d) => d['title'] = 'alt vom PC');
    pcTask.updatedAt = 1; // older than the phone's edit
    await pcSync.syncNow();
    expect(Task(pc.byUid(task.uid)!).title, 'neu vom Handy');
    expect(pcSync.pending, 0);
  });

  test('unknown fields from the iPhone survive an edit here', () {
    final store = Store();
    store.applyRemote(
      uid: 'A',
      updatedAt: 10,
      type: Kind.task,
      deleted: false,
      data: {'uid': 'A', 'title': 'x', 'futureField': 42},
    );
    store.update(store.byUid('A')!, (d) => d['title'] = 'y');
    expect(store.byUid('A')!.data['futureField'], 42);
    expect(store.byUid('A')!.updatedAt, greaterThan(10));
    expect(store.applyRemote(uid: 'A', updatedAt: 11, type: Kind.task, deleted: false, data: {}), isFalse);
  });

  test('server addresses are normalised', () {
    expect(SyncClient.normalizeServer('margin-connector.max.workers.dev/'), 'https://margin-connector.max.workers.dev');
    expect(SyncClient.normalizeServer(' https://a.b/c '), 'https://a.b');
    expect(SyncClient.strongEnough('kurz'), isFalse);
    expect(SyncClient.strongEnough(SyncClient.suggestPassphrase()), isTrue);
  });
}
