import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/security/password_hasher.dart';
import '../data/models.dart';
import '../data/shop_repository.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Session utilisateur : connexion, blocage après échecs répétés,
/// verrouillage automatique après inactivité.
class Session extends ChangeNotifier {
  Session(this.repo, {this.hashIterations = PasswordHasher.defaultIterations});

  final ShopRepository repo;

  /// Coût PBKDF2 des nouveaux hashes (réduit uniquement dans les tests).
  final int hashIterations;

  static const int maxAttempts = 5;
  static const Duration baseLockout = Duration(seconds: 30);
  static const Duration maxLockout = Duration(minutes: 15);

  AppUser? _user;
  bool _locked = false;
  DateTime _lastActivity = DateTime.now();
  int _unlockFailures = 0;

  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLocked => _locked;
  int get userId => _user!.id;

  // --------------------------------------------------------------------
  // Validation
  // --------------------------------------------------------------------

  static String? validateEmail(String? v) {
    final email = v?.trim() ?? '';
    if (email.isEmpty) return 'L\'email est obligatoire';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(email)) return 'Email invalide';
    return null;
  }

  /// Au moins 8 caractères, dont une lettre et un chiffre.
  static String? validatePassword(String? v) {
    final p = v ?? '';
    if (p.length < 8) return 'Au moins 8 caractères';
    if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
      return 'Doit contenir au moins une lettre et un chiffre';
    }
    return null;
  }

  // --------------------------------------------------------------------
  // Inscription / connexion
  // --------------------------------------------------------------------

  /// Crée le compte et retourne le code de secours (à afficher une seule fois).
  Future<String> register({
    required String name,
    required String email,
    required String password,
    required String businessName,
  }) async {
    if (name.trim().isEmpty || businessName.trim().isEmpty) {
      throw const AuthException('Nom et nom de la boutique sont obligatoires');
    }
    final emailError = validateEmail(email);
    if (emailError != null) throw AuthException(emailError);
    final pwdError = validatePassword(password);
    if (pwdError != null) throw AuthException(pwdError);
    if (await repo.findUserRowByEmail(email) != null) {
      throw const AuthException('Un compte existe déjà avec cet email');
    }
    final hash = await _hash(password);
    final id = await repo.createUser(name: name, email: email, passwordHash: hash, businessName: businessName);
    final code = generateRecoveryCode();
    await repo.setRecoveryHash(id, await _hash(normalizeRecoveryCode(code)));
    return code;
  }

  Future<void> login(String email, String password) async {
    final row = await repo.findUserRowByEmail(email);
    if (row == null) {
      // Même coût de calcul qu'un vrai compte : ne révèle pas si l'email existe.
      await _hash(password);
      throw const AuthException('Email ou mot de passe incorrect');
    }
    final userId = row['id'] as int;
    final lockedUntil = row['lockedUntil'] == null ? null : DateTime.parse(row['lockedUntil'] as String);
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      throw AuthException('Trop de tentatives. Réessayez dans ${_humanDelay(lockedUntil.difference(DateTime.now()))}.');
    }

    final stored = row['passwordHash'] as String;
    final ok = await compute(_verifyIsolate, [password, stored]);
    if (!ok) {
      // Même message qu'un email inconnu : on ne révèle pas quels comptes existent.
      await _registerFailure(row, 'Échec de connexion', 'Email ou mot de passe incorrect');
    }

    await repo.updateLoginState(userId, failedAttempts: 0);
    if (PasswordHasher.isLegacy(stored)) {
      // Migration transparente de l'ancien hash SHA256 non salé.
      await repo.setPasswordHash(userId, await _hash(password));
    }
    await repo.audit(userId, 'Sécurité', 'Connexion');
    _user = AppUser.fromMap((await repo.findUserRowById(userId))!);
    _locked = false;
    _unlockFailures = 0;
    _lastActivity = DateTime.now();
    notifyListeners();
  }

  /// Compte un échec (connexion ou code de secours) et bloque le compte au-delà de [maxAttempts].
  Future<Never> _registerFailure(Map<String, Object?> row, String label, String message) async {
    final userId = row['id'] as int;
    final failed = (row['failedAttempts'] as int) + 1;
    DateTime? until;
    if (failed >= maxAttempts) {
      final factor = pow(2, failed - maxAttempts).toInt();
      final delay = baseLockout * factor;
      until = DateTime.now().add(delay > maxLockout ? maxLockout : delay);
    }
    await repo.updateLoginState(userId, failedAttempts: failed, lockedUntil: until);
    await repo.audit(userId, 'Sécurité', '$label ($failed)');
    if (until != null) {
      throw AuthException('Trop de tentatives. Compte bloqué ${_humanDelay(until.difference(DateTime.now()))}.');
    }
    throw AuthException(message);
  }

  // --------------------------------------------------------------------
  // Code de secours (mot de passe oublié)
  // --------------------------------------------------------------------

  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Code de 12 caractères sans caractères ambigus (0/O, 1/I) : « ABCD-EFGH-JKLM ».
  static String generateRecoveryCode() {
    final rnd = Random.secure();
    final chars = List.generate(12, (_) => _codeAlphabet[rnd.nextInt(_codeAlphabet.length)]).join();
    return '${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
  }

  static String normalizeRecoveryCode(String code) => code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Réinitialise le mot de passe avec le code de secours. Retourne le NOUVEAU code
  /// (l'ancien ne fonctionne plus). Les échecs comptent pour le blocage du compte.
  Future<String> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final pwdError = validatePassword(newPassword);
    if (pwdError != null) throw AuthException(pwdError);
    const invalid = 'Email ou code de secours incorrect';
    final row = await repo.findUserRowByEmail(email);
    if (row == null) {
      await _hash(code);
      throw const AuthException(invalid);
    }
    final lockedUntil = row['lockedUntil'] == null ? null : DateTime.parse(row['lockedUntil'] as String);
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      throw AuthException('Trop de tentatives. Réessayez dans ${_humanDelay(lockedUntil.difference(DateTime.now()))}.');
    }
    final stored = row['recoveryHash'] as String?;
    if (stored == null) {
      throw const AuthException(
        'Ce compte n\'a pas de code de secours. Sans le mot de passe, les données ne peuvent pas être récupérées.',
      );
    }
    final ok = await compute(_verifyIsolate, [normalizeRecoveryCode(code), stored]);
    if (!ok) await _registerFailure(row, 'Échec du code de secours', invalid);

    final userId = row['id'] as int;
    await repo.setPasswordHash(userId, await _hash(newPassword));
    final next = generateRecoveryCode();
    await repo.setRecoveryHash(userId, await _hash(normalizeRecoveryCode(next)));
    await repo.updateLoginState(userId, failedAttempts: 0);
    await repo.audit(userId, 'Sécurité', 'Mot de passe réinitialisé avec le code de secours');
    return next;
  }

  /// Génère un nouveau code de secours (l'ancien est invalidé). Exige le mot de passe.
  Future<String> regenerateRecoveryCode(String password) async {
    final row = await repo.findUserRowById(userId);
    if (row == null || !await compute(_verifyIsolate, [password, row['passwordHash'] as String])) {
      await repo.audit(userId, 'Sécurité', 'Échec de génération du code de secours');
      throw const AuthException('Mot de passe incorrect');
    }
    final code = generateRecoveryCode();
    await repo.setRecoveryHash(userId, await _hash(normalizeRecoveryCode(code)));
    await repo.audit(userId, 'Sécurité', 'Nouveau code de secours généré');
    _user = AppUser.fromMap((await repo.findUserRowById(userId))!);
    notifyListeners();
    return code;
  }

  void logout() {
    if (_user != null) repo.audit(_user!.id, 'Sécurité', 'Déconnexion');
    _user = null;
    _locked = false;
    notifyListeners();
  }

  // --------------------------------------------------------------------
  // Verrouillage automatique
  // --------------------------------------------------------------------

  void touch() => _lastActivity = DateTime.now();

  /// À appeler périodiquement et au retour au premier plan.
  void checkInactivity() {
    final u = _user;
    if (u == null || _locked || u.autoLockMinutes <= 0) return;
    if (DateTime.now().difference(_lastActivity) >= Duration(minutes: u.autoLockMinutes)) lock();
  }

  void lock() {
    if (_user == null) return;
    _locked = true;
    notifyListeners();
  }

  Future<void> unlock(String password) async {
    final row = await repo.findUserRowById(userId);
    final ok = row != null && await compute(_verifyIsolate, [password, row['passwordHash'] as String]);
    if (!ok) {
      _unlockFailures++;
      await repo.audit(userId, 'Sécurité', 'Échec de déverrouillage ($_unlockFailures)');
      if (_unlockFailures >= maxAttempts) {
        logout();
        throw const AuthException('Trop d\'échecs : vous avez été déconnecté.');
      }
      throw AuthException(
        'Mot de passe incorrect (${maxAttempts - _unlockFailures} essai${maxAttempts - _unlockFailures > 1 ? 's' : ''} restant${maxAttempts - _unlockFailures > 1 ? 's' : ''})',
      );
    }
    _unlockFailures = 0;
    _locked = false;
    _lastActivity = DateTime.now();
    notifyListeners();
  }

  // --------------------------------------------------------------------
  // Profil
  // --------------------------------------------------------------------

  Future<void> updateSettings(AppUser updated) async {
    if (updated.name.trim().isEmpty || updated.businessName.trim().isEmpty) {
      throw const AuthException('Nom et nom de la boutique sont obligatoires');
    }
    await repo.updateUserSettings(updated);
    _user = updated;
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async {
    final row = await repo.findUserRowById(userId);
    if (row == null || !await compute(_verifyIsolate, [current, row['passwordHash'] as String])) {
      await repo.audit(userId, 'Sécurité', 'Échec de changement de mot de passe');
      throw const AuthException('Mot de passe actuel incorrect');
    }
    final err = validatePassword(next);
    if (err != null) throw AuthException(err);
    if (current == next) throw const AuthException('Le nouveau mot de passe doit être différent');
    await repo.setPasswordHash(userId, await _hash(next));
    await repo.audit(userId, 'Sécurité', 'Mot de passe modifié');
  }

  Future<String> _hash(String password) => compute(_hashIsolate, [password, '$hashIterations']);

  static String _humanDelay(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes + 1} min';
    return '${d.inSeconds + 1} s';
  }
}

String _hashIsolate(List<String> args) => PasswordHasher.hash(args[0], iterations: int.parse(args[1]));

bool _verifyIsolate(List<String> args) => PasswordHasher.verify(args[0], args[1]);
