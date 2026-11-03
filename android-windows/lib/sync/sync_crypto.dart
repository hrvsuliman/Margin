import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption of sync records, exactly as in docs/SYNC.md
/// (reference implementation: connector/sync-crypto.mjs).
abstract final class SyncCrypto {
  static const iterations = 310000;
  static const salt = 'margin-sync-v1';

  static final _hmac = Hmac.sha256();
  static final _aes = AesGcm.with256bits();

  /// Passphrase → AES key and vault token. Takes a few seconds; runs in the background.
  static Future<SyncKeys> deriveKeys(String passphrase) => Isolate.run(() => _derive(passphrase));

  static Future<SyncKeys> _derive(String passphrase) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final master = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase.trim())),
      nonce: utf8.encode(salt),
    );
    final prk = await _mac(Uint8List(32), await master.extractBytes());
    final key = await _mac(prk, [...utf8.encode('margin-sync-v1 key'), 1]);
    final vault = await _mac(prk, [...utf8.encode('margin-sync-v1 vault'), 1]);
    return SyncKeys(Uint8List.fromList(key), hex(vault));
  }

  static Future<List<int>> _mac(List<int> key, List<int> message) async =>
      (await _hmac.calculateMac(message, secretKey: SecretKey(key))).bytes;

  static List<int> _aad(String uid, int updatedAt) => utf8.encode('$uid|$updatedAt');

  /// {type, deleted, data} → base64(nonce ‖ ciphertext ‖ tag).
  static Future<String> seal(
    List<int> key,
    String uid,
    int updatedAt,
    Map<String, dynamic> payload, {
    List<int>? nonce,
  }) async {
    final random = Random.secure();
    final iv = nonce ?? List<int>.generate(12, (_) => random.nextInt(256));
    final plain = utf8.encode(jsonEncode({'v': 1, ...payload}));
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key), nonce: iv, aad: _aad(uid, updatedAt));
    return base64.encode([...iv, ...box.cipherText, ...box.mac.bytes]);
  }

  /// blob → {v, type, deleted, data}. Throws if the key is wrong or the blob was changed.
  static Future<Map<String, dynamic>> open(List<int> key, String uid, int updatedAt, String blob) async {
    final bytes = base64.decode(blob);
    if (bytes.length < 28) throw const FormatException('blob too short');
    final box = SecretBox(
      bytes.sublist(12, bytes.length - 16),
      nonce: bytes.sublist(0, 12),
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    final plain = await _aes.decrypt(box, secretKey: SecretKey(key), aad: _aad(uid, updatedAt));
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  static String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class SyncKeys {
  const SyncKeys(this.key, this.vault);

  /// 32 bytes, AES-256-GCM.
  final Uint8List key;

  /// 64 hex characters; the only thing the server learns.
  final String vault;
}
