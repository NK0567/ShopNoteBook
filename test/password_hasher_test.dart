import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopnotbook/core/security/password_hasher.dart';

void main() {
  test('hash salé : deux hachages du même mot de passe diffèrent', () {
    final a = PasswordHasher.hash('Secret123', iterations: 1000);
    final b = PasswordHasher.hash('Secret123', iterations: 1000);
    expect(a, isNot(b));
    expect(a, startsWith('pbkdf2\$1000\$'));
    expect(PasswordHasher.verify('Secret123', a), isTrue);
    expect(PasswordHasher.verify('secret123', a), isFalse);
  });

  test('vecteur de référence PBKDF2-HMAC-SHA256 (RFC 7914)', () {
    // P="passwd", S="salt", c=1, dkLen=32
    const stored = 'pbkdf2\$1\$c2FsdA==\$VawEblbjCJ/sFpHCJUS2BflBhSFt3gRl5oudV8INrLw=';
    expect(PasswordHasher.verify('passwd', stored), isTrue);
    // P="Password", S="NaCl", c=80000
    const stored2 = 'pbkdf2\$80000\$TmFDbA==\$TdzY9guYviGDDO5e8icB+WQaRBjQTAQUrv8Ih2s0q1Y=';
    expect(PasswordHasher.verify('Password', stored2), isTrue);
  });

  test('compatibilité avec les anciens comptes (SHA256 sans sel)', () {
    final legacy = sha256.convert('ancienMdp'.codeUnits).toString();
    expect(PasswordHasher.isLegacy(legacy), isTrue);
    expect(PasswordHasher.verify('ancienMdp', legacy), isTrue);
    expect(PasswordHasher.verify('autre', legacy), isFalse);
  });

  test('format invalide rejeté', () {
    expect(PasswordHasher.verify('x', 'n\'importe quoi'), isFalse);
  });
}
