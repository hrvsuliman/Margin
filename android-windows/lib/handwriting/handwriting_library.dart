// Handwriting profiles on this device. They are not synced (docs/SYNC.md: too
// large for v1), so they come from an iPhone backup file instead, which has
// them as `profiles` and `glyphs` (BackupFile.ProfileDTO / GlyphDTO).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'analysis.dart';
import 'geometry.dart';
import 'handwriting_font.dart';

/// A handwriting profile, as the iPhone's `ProfileDTO`.
extension type HandwritingProfile(Map<String, dynamic> data) {
  String get uid => data['uid'] as String? ?? '';
  String get name => data['name'] as String? ?? '';
  bool get isDefault => data['isDefault'] == true;
  String get createdAt => data['createdAt'] as String? ?? '';
  double _number(String key, double fallback) => data[key] is num ? (data[key] as num).toDouble() : fallback;
  double get letterSpacing => _number('letterSpacing', 0.14);
  double get wordSpacing => _number('wordSpacing', 0.75);
  double get slantAdjust => _number('slantAdjust', 0);
  double get variation => _number('variation', 1);

  String get displayName => name.trim().isEmpty ? 'Handschrift' : name.trim();
}

/// What a backup import brought in.
class ImportSummary {
  const ImportSummary({this.profiles = 0, this.glyphs = 0, this.notes = 0, this.skippedNotes = 0});
  final int profiles;
  final int glyphs;
  final int notes;

  /// Notes that already exist here (kept as they are).
  final int skippedNotes;
}

class HandwritingLibrary extends ChangeNotifier {
  HandwritingLibrary([this.file]);

  /// Null in tests (memory only).
  final File? file;
  final List<Map<String, dynamic>> _profiles = [];
  final List<Map<String, dynamic>> _glyphs = [];
  final Map<String, HandwritingFont> _fonts = {};

  static Future<HandwritingLibrary> load(File file) async {
    final library = HandwritingLibrary(file);
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        library._read(json);
      } catch (error) {
        await file.copy('${file.path}.defekt-${DateTime.now().millisecondsSinceEpoch}');
        debugPrint('Margin: could not read ${file.path}: $error');
      }
    }
    return library;
  }

  void _read(Map<String, dynamic> json) {
    for (final p in json['profiles'] as List? ?? const []) {
      _profiles.add(Map<String, dynamic>.from(p as Map));
    }
    for (final g in json['glyphs'] as List? ?? const []) {
      _glyphs.add(Map<String, dynamic>.from(g as Map));
    }
  }

  /// Oldest first, like the iPhone's profile list.
  List<HandwritingProfile> get profiles =>
      _profiles.map(HandwritingProfile.new).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  HandwritingProfile? profile(String? uid) {
    if (uid == null) return null;
    for (final p in _profiles) {
      if (p['uid'] == uid) return HandwritingProfile(p);
    }
    return null;
  }

  /// The profile marked as default, otherwise the oldest (NoteRendering.defaultProfile).
  HandwritingProfile? get defaultProfile {
    final all = profiles;
    for (final p in all) {
      if (p.isDefault) return p;
    }
    return all.isEmpty ? null : all.first;
  }

  /// The note's own profile, otherwise the default one (NoteRendering.profile).
  HandwritingProfile? profileFor(String? noteProfile) => profile(noteProfile) ?? defaultProfile;

  List<Map<String, dynamic>> _glyphsOf(String profileUid) =>
      _glyphs.where((g) => g['profile'] == profileUid).toList()
        ..sort((a, b) => (a['createdAt'] as String? ?? '').compareTo(b['createdAt'] as String? ?? ''));

  /// Characters written in this profile (each counted once).
  int characterCount(String profileUid) => _glyphsOf(profileUid).map((g) => g['character']).toSet().length;

  FontSource source(String profileUid) {
    final profile = this.profile(profileUid);
    if (profile == null) return FontSource.empty;
    final glyphs = <String, List<GlyphInput>>{};
    for (final g in _glyphsOf(profileUid)) {
      final character = g['character'] as String? ?? '';
      final strokes = g['strokes'];
      if (character.isEmpty || strokes is! String) continue;
      final geometry = GlyphStrokes.decodeBase64(strokes);
      if (geometry.strokes.isEmpty && geometry.outlines.isEmpty) continue;
      glyphs.putIfAbsent(character, () => []).add(GlyphInput(
            uid: g['uid'] as String? ?? '',
            strokes: geometry.strokes,
            outlines: geometry.outlines,
            scale: (g['scale'] as num?)?.toDouble() ?? 1,
            baselineOffset: (g['baselineOffset'] as num?)?.toDouble() ?? 0,
          ));
    }
    return FontSource(
      glyphs: glyphs,
      letterSpacing: profile.letterSpacing,
      wordSpacing: profile.wordSpacing,
      slantAdjust: profile.slantAdjust,
      variation: profile.variation,
    );
  }

  /// The font of a profile at a pen weight, built once and kept.
  HandwritingFont font(String? profileUid, double penRatio) {
    final key = '${profileUid ?? '-'}@$penRatio';
    return _fonts[key] ??= HandwritingFont(
      profileUid == null ? FontSource.empty : source(profileUid),
      penRatio: penRatio,
    );
  }

  /// Takes the handwriting of an iPhone backup. A profile that is already here
  /// (same uid) is replaced, so importing a newer backup updates it.
  ImportSummary importProfiles(Map<String, dynamic> backup) {
    final profiles = [for (final p in backup['profiles'] as List? ?? const []) Map<String, dynamic>.from(p as Map)];
    final glyphs = [for (final g in backup['glyphs'] as List? ?? const []) Map<String, dynamic>.from(g as Map)];
    var glyphCount = 0;
    final hadDefault = _profiles.any((p) => p['isDefault'] == true);
    for (final profile in profiles) {
      final uid = profile['uid'];
      if (uid is! String) continue;
      _profiles.removeWhere((p) => p['uid'] == uid);
      _glyphs.removeWhere((g) => g['profile'] == uid);
      // Keep this device's choice of default handwriting.
      if (hadDefault) profile['isDefault'] = false;
      _profiles.add(profile);
      final own = glyphs.where((g) => g['profile'] == uid).toList();
      _glyphs.addAll(own);
      glyphCount += own.length;
    }
    _changed();
    return ImportSummary(profiles: profiles.length, glyphs: glyphCount);
  }

  void setDefault(String uid) {
    for (final p in _profiles) {
      p['isDefault'] = p['uid'] == uid;
    }
    _changed();
  }

  void rename(String uid, String name) {
    for (final p in _profiles) {
      if (p['uid'] == uid) p['name'] = name;
    }
    _changed();
  }

  void delete(String uid) {
    _profiles.removeWhere((p) => p['uid'] == uid);
    _glyphs.removeWhere((g) => g['profile'] == uid);
    _changed();
  }

  void _changed() {
    _fonts.clear();
    notifyListeners();
    save();
  }

  Future<void> _saving = Future.value();

  /// Writes the file. Writes never overlap.
  Future<void> save() => _saving = _saving.then((_) => _write()).catchError((Object error) {
        debugPrint('Margin: saving handwriting failed: $error');
      });

  Future<void> _write() async {
    final target = file;
    if (target == null) return;
    final json = jsonEncode({
      'format': 'margin-handwriting',
      'version': 1,
      'profiles': _profiles,
      'glyphs': _glyphs,
    });
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(json, flush: true);
    await temp.rename(target.path);
  }
}
