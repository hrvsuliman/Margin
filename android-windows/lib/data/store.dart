import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// One synced object: a subject, a task, a note … `data` holds exactly the
/// fields of the iPhone backup DTO (see docs/SYNC.md), including fields this
/// app doesn't know, so editing here never drops what the iPhone wrote.
class Rec {
  Rec({
    required this.type,
    required this.uid,
    required this.data,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = false,
    this.problem,
  });

  final String type;
  final String uid;
  Map<String, dynamic> data;

  /// Last change in milliseconds since 1970 (UTC). Decides sync conflicts.
  int updatedAt;
  bool deleted;

  /// Changed here and not yet accepted by the sync server.
  bool dirty;

  /// Why the server refused this record ("tooLarge", "invalid"), if it did.
  String? problem;

  String str(String key) => data[key] is String ? data[key] as String : '';
  int integer(String key, [int fallback = 0]) => data[key] is num ? (data[key] as num).round() : fallback;
  double number(String key, [double fallback = 0]) => data[key] is num ? (data[key] as num).toDouble() : fallback;
  bool flag(String key, [bool fallback = false]) => data[key] is bool ? data[key] as bool : fallback;
  String? ref(String key) => data[key] is String && (data[key] as String).isNotEmpty ? data[key] as String : null;

  Map<String, dynamic> toJson() => {
        'type': type,
        'uid': uid,
        'updatedAt': updatedAt,
        if (deleted) 'deleted': true,
        if (dirty) 'dirty': true,
        if (problem != null) 'problem': problem,
        'data': data,
      };

  factory Rec.fromJson(Map<String, dynamic> json) => Rec(
        type: json['type'] as String,
        uid: json['uid'] as String,
        updatedAt: (json['updatedAt'] as num).toInt(),
        deleted: json['deleted'] == true,
        dirty: json['dirty'] == true,
        problem: json['problem'] as String?,
        data: Map<String, dynamic>.from(json['data'] as Map),
      );
}

/// A random UUID in Swift's format (uppercase).
String newUid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// All of Margin's data on this device, kept in one JSON file.
/// Widgets listen to it; every change is saved shortly after.
class Store extends ChangeNotifier {
  Store([this.file]);

  /// Null in tests (memory only).
  final File? file;
  final Map<String, Rec> _records = {};

  /// Sync position on the server (see docs/SYNC.md).
  int cursor = 0;

  /// Settings that stay on this device.
  Map<String, dynamic> settings = {};

  /// Called after every local change (the sync client debounces it).
  VoidCallback? onLocalChange;
  Timer? _saveTimer;

  static Future<Store> load(File file) async {
    final store = Store(file);
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        store.cursor = (json['cursor'] as num?)?.toInt() ?? 0;
        store.settings = Map<String, dynamic>.from(json['settings'] as Map? ?? {});
        for (final raw in json['records'] as List? ?? []) {
          final rec = Rec.fromJson(Map<String, dynamic>.from(raw as Map));
          store._records[rec.uid] = rec;
        }
      } catch (error) {
        // Keep the unreadable file instead of overwriting it with nothing.
        await file.copy('${file.path}.defekt-${DateTime.now().millisecondsSinceEpoch}');
        debugPrint('Margin: could not read ${file.path}: $error');
      }
    }
    return store;
  }

  Iterable<Rec> get allRecords => _records.values;

  Iterable<Rec> records(String type) => _records.values.where((r) => r.type == type && !r.deleted);

  Rec? byUid(String? uid) {
    if (uid == null) return null;
    final rec = _records[uid];
    return rec == null || rec.deleted ? null : rec;
  }

  /// Any record, also deleted ones (for sync).
  Rec? raw(String uid) => _records[uid];

  Rec create(String type, Map<String, dynamic> data) {
    final uid = (data['uid'] as String?) ?? newUid();
    final rec = Rec(type: type, uid: uid, data: {...data, 'uid': uid}, updatedAt: 0);
    _records[uid] = rec;
    touch(rec);
    return rec;
  }

  /// Changes fields of a record and marks it for sync.
  void update(Rec rec, void Function(Map<String, dynamic> data) change) {
    change(rec.data);
    touch(rec);
  }

  void delete(Rec rec) {
    rec.deleted = true;
    rec.data = {'uid': rec.uid};
    touch(rec);
  }

  void touch(Rec rec) {
    rec.updatedAt = max(DateTime.now().millisecondsSinceEpoch, rec.updatedAt + 1);
    rec.dirty = true;
    rec.problem = null;
    notifyListeners();
    _scheduleSave();
    onLocalChange?.call();
  }

  /// Takes a record from the server if it's newer than ours. Returns whether it was applied.
  bool applyRemote({
    required String uid,
    required int updatedAt,
    required String type,
    required bool deleted,
    required Map<String, dynamic> data,
  }) {
    final local = _records[uid];
    if (local != null && local.updatedAt >= updatedAt) return false;
    _records[uid] = Rec(
      type: type,
      uid: uid,
      updatedAt: updatedAt,
      deleted: deleted,
      data: deleted ? {'uid': uid} : {...data, 'uid': uid},
    );
    return true;
  }

  /// After sync changed records or flags.
  void syncChanged() {
    notifyListeners();
    _scheduleSave();
  }

  void setSetting(String key, Object? value) {
    settings[key] = value;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), flush);
  }

  Future<void> _saving = Future.value();

  /// Writes the file now. Writes never overlap.
  Future<void> flush() {
    _saveTimer?.cancel();
    return _saving = _saving.then((_) => _write()).catchError((Object error) {
      debugPrint('Margin: saving failed: $error');
    });
  }

  Future<void> _write() async {
    final target = file;
    if (target == null) return;
    final json = jsonEncode({
      'format': 'margin-device-store',
      'version': 1,
      'cursor': cursor,
      'settings': settings,
      'records': _records.values.map((r) => r.toJson()).toList(),
    });
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(json, flush: true);
    await temp.rename(target.path);
  }
}
