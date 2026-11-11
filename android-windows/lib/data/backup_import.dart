// Reads an iPhone backup file ("Margin-Backup-2026-11-11.json", Einstellungen ›
// Backup sichern on the iPhone) for what sync doesn't carry yet: the handwriting.
// Notes from the backup that aren't on this device yet are added as well.

import 'dart:convert';

import '../handwriting/handwriting_library.dart';
import 'entities.dart';
import 'store.dart';

abstract final class BackupImport {
  /// The backup as JSON. Throws a [FormatException] with a message for the user.
  static Map<String, dynamic> parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Diese Datei ist kein Margin-Backup.');
    }
    if (json is! Map<String, dynamic> || json['format'] != 'margin-backup') {
      throw const FormatException('Diese Datei ist kein Margin-Backup.');
    }
    if ((json['version'] as num? ?? 0) > 5) {
      throw const FormatException('Dieses Backup stammt aus einer neueren Margin-Version. Bitte aktualisiere die App zuerst.');
    }
    return json;
  }

  static ImportSummary apply(Map<String, dynamic> backup, Store store, HandwritingLibrary library) {
    final handwriting = library.importProfiles(backup);
    var notes = 0;
    var skipped = 0;
    for (final raw in backup['notes'] as List? ?? const []) {
      final data = Map<String, dynamic>.from(raw as Map);
      final uid = data['uid'];
      if (uid is! String) continue;
      // Already here (or deleted here): this device's version stays.
      if (store.raw(uid) != null) {
        skipped++;
        continue;
      }
      store.create(Kind.note, {...defaultsFor(Kind.note), ...data});
      notes++;
    }
    return ImportSummary(
      profiles: handwriting.profiles,
      glyphs: handwriting.glyphs,
      notes: notes,
      skippedNotes: skipped,
    );
  }
}
