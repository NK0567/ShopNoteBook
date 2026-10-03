import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hachage des mots de passe avec PBKDF2-HMAC-SHA256 + sel aléatoire.
///
/// Format stocké : `pbkdf2$<iterations>$<sel base64>$<hash base64>`.
/// L'ancien format (SHA256 sans sel, 64 caractères hex) est encore reconnu
/// pour permettre la migration transparente des comptes existants.
class PasswordHasher {
  static const int defaultIterations = 60000;
  static const int _saltLength = 16;
  static const int _keyLength = 32;

  static String hash(String password, {int iterations = defaultIterations}) {
    final salt = _randomBytes(_saltLength);
    final key = _pbkdf2(utf8.encode(password), salt, iterations, _keyLength);
    return 'pbkdf2\$$iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  static bool verify(String password, String stored) {
    if (isLegacy(stored)) {
      final legacy = sha256.convert(password.codeUnits).toString();
      return _constantTimeEquals(utf8.encode(legacy), utf8.encode(stored));
    }
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final actual =
        _pbkdf2(utf8.encode(password), salt, iterations, expected.length);
    return _constantTimeEquals(actual, expected);
  }

  /// Vrai si le hash provient de l'ancienne version (SHA256 sans sel).
  static bool isLegacy(String stored) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(stored);

  static Uint8List _pbkdf2(
      List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength / 32).ceil();
    final out = BytesBuilder();
    for (var i = 1; i <= blocks; i++) {
      final block = Uint8List.fromList(
          [...salt, (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff]);
      var u = hmac.convert(block).bytes;
      final t = Uint8List.fromList(u);
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, keyLength));
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rnd.nextInt(256)));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
