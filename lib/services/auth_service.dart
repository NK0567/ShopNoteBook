import 'package:crypto/crypto.dart';
import '../models/user.dart';
import 'database_service.dart';

/// Service de gestion de l'authentification des utilisateurs
/// Gère l'enregistrement, la connexion et la validation des identifiants
class AuthService {
  // Variable globale pour stocker l'utilisateur actuellement connecté
  static User? _currentUser;

  /// Getter pour accéder à l'utilisateur actuellement connecté
  static User? get currentUser => _currentUser;

  /// Vérifie si un utilisateur est actuellement authentifié
  static bool get isAuthenticated => _currentUser != null;

  /// Hache le mot de passe en utilisant SHA256 pour la sécurité
  /// N'utilise pas de salt pour la simplicité (dans une vraie app, utiliser bcrypt)
  static String _hashPassword(String password) {
    return sha256.convert(password.codeUnits).toString();
  }

  /// Valide le format de l'email (vérification basique)
  static bool _isValidEmail(String email) {
    // Expression régulière pour valider les emails
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  /// Valide la force du mot de passe
  /// Exige au moins 6 caractères
  static bool _isValidPassword(String password) {
    return password.length >= 6;
  }

  /// Enregistre un nouvel utilisateur dans l'application
  /// Retourne true si l'inscription est réussie, false sinon
  static Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String businessName,
  }) async {
    // Vérifie que tous les champs sont remplis
    if (name.isEmpty || email.isEmpty || password.isEmpty || businessName.isEmpty) {
      return false;
    }

    // Valide le format de l'email
    if (!_isValidEmail(email)) {
      return false;
    }

    // Valide la force du mot de passe
    if (!_isValidPassword(password)) {
      return false;
    }

    // Vérifie si l'email n'est pas déjà utilisé
    final existingUser = await DatabaseService.getUserByEmail(email);
    if (existingUser != null) {
      return false; // Email déjà enregistré
    }

    try {
      // Crée un nouvel utilisateur avec les données fournies
      final newUser = User(
        name: name,
        email: email,
        passwordHash: _hashPassword(password), // Hache le mot de passe
        businessName: businessName,
        createdAt: DateTime.now().toIso8601String(),
      );

      // Enregistre l'utilisateur dans la base de données
      await DatabaseService.createUser(newUser);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Connecte un utilisateur existant à l'application
  /// Retourne true si la connexion est réussie, false sinon
  static Future<bool> login({
    required String email,
    required String password,
  }) async {
    // Vérifie que l'email et le mot de passe sont fournis
    if (email.isEmpty || password.isEmpty) {
      return false;
    }

    try {
      // Récupère l'utilisateur par email depuis la base de données
      final user = await DatabaseService.getUserByEmail(email);

      // Vérifie que l'utilisateur existe
      if (user == null) {
        return false;
      }

      // Vérifie que le mot de passe fourni correspond au hash enregistré
      final passwordHash = _hashPassword(password);
      if (user.passwordHash != passwordHash) {
        return false; // Mot de passe incorrect
      }

      // Définit l'utilisateur comme actuellement connecté
      _currentUser = user;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Déconnecte l'utilisateur actuellement connecté
  static void logout() {
    _currentUser = null;
  }

  /// Met à jour l'utilisateur actuellement connecté (pour les changements internes)
  static void updateCurrentUser(User user) {
    _currentUser = user;
  }

  /// Met à jour le profil de l'utilisateur actuellement connecté
  /// Permet de modifier le nom, le nom de la boutique et les paramètres d'alerte
  static Future<bool> updateProfile({
    required String name,
    required String businessName,
    required int criticalStockThreshold,
    required int warningStockThreshold,
  }) async {
    // Vérifie qu'un utilisateur est connecté
    if (_currentUser == null) {
      return false;
    }

    try {
      // Crée une copie mise à jour de l'utilisateur
      final updatedUser = User(
        id: _currentUser!.id,
        name: name,
        email: _currentUser!.email,
        passwordHash: _currentUser!.passwordHash,
        businessName: businessName,
        criticalStockThreshold: criticalStockThreshold,
        warningStockThreshold: warningStockThreshold,
        warningColor: _currentUser!.warningColor,
        criticalColor: _currentUser!.criticalColor,
        createdAt: _currentUser!.createdAt,
      );

      // Enregistre les modifications en base de données
      await DatabaseService.updateUser(updatedUser);

      // Met à jour l'utilisateur local
      _currentUser = updatedUser;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Met à jour les couleurs personnalisées d'alerte
  static Future<bool> updateAlertColors({
    required String warningColor,
    required String criticalColor,
  }) async {
    // Vérifie qu'un utilisateur est connecté
    if (_currentUser == null) {
      return false;
    }

    try {
      // Crée une copie avec les nouvelles couleurs
      final updatedUser = User(
        id: _currentUser!.id,
        name: _currentUser!.name,
        email: _currentUser!.email,
        passwordHash: _currentUser!.passwordHash,
        businessName: _currentUser!.businessName,
        criticalStockThreshold: _currentUser!.criticalStockThreshold,
        warningStockThreshold: _currentUser!.warningStockThreshold,
        warningColor: warningColor,
        criticalColor: criticalColor,
        createdAt: _currentUser!.createdAt,
      );

      // Enregistre les modifications
      await DatabaseService.updateUser(updatedUser);
      _currentUser = updatedUser;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Change le mot de passe de l'utilisateur actuellement connecté
  static Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // Vérifie qu'un utilisateur est connecté
    if (_currentUser == null) {
      return false;
    }

    // Vérifie que le mot de passe actuel est correct
    if (_hashPassword(currentPassword) != _currentUser!.passwordHash) {
      return false;
    }

    // Valide la force du nouveau mot de passe
    if (!_isValidPassword(newPassword)) {
      return false;
    }

    try {
      // Crée une copie avec le nouveau mot de passe hashé
      final updatedUser = User(
        id: _currentUser!.id,
        name: _currentUser!.name,
        email: _currentUser!.email,
        passwordHash: _hashPassword(newPassword),
        businessName: _currentUser!.businessName,
        criticalStockThreshold: _currentUser!.criticalStockThreshold,
        warningStockThreshold: _currentUser!.warningStockThreshold,
        warningColor: _currentUser!.warningColor,
        criticalColor: _currentUser!.criticalColor,
        createdAt: _currentUser!.createdAt,
      );

      // Enregistre le nouveau mot de passe
      await DatabaseService.updateUser(updatedUser);
      _currentUser = updatedUser;
      return true;
    } catch (e) {
      return false;
    }
  }
}
