/// Modèle représentant un utilisateur de l'application
/// Contient les informations de compte de chaque commerçant
class User {
  // Identifiant unique de l'utilisateur
  final int? id;
  
  // Nom complet du propriétaire de la boutique
  final String name;
  
  // Adresse email unique pour l'authentification
  final String email;
  
  // Mot de passe hashé pour la sécurité
  final String passwordHash;
  
  // Nom de la boutique/entreprise
  final String businessName;
  
  // Seuil d'alerte pour stock faible (en pourcentage ou quantité)
  final int criticalStockThreshold;
  
  // Seuil d'alerte pour stock critique
  final int warningStockThreshold;
  
  // Couleur personnalisée pour les alertes orange (réapprov recommandée)
  final String warningColor;
  
  // Couleur personnalisée pour les alertes rouge (réapprov urgente)
  final String criticalColor;
  
  // Date de création du compte
  final String createdAt;

  /// Constructeur du modèle User
  User({
    this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.businessName,
    this.criticalStockThreshold = 5,
    this.warningStockThreshold = 10,
    this.warningColor = '#FF9800', // Orange par défaut
    this.criticalColor = '#F44336', // Rouge par défaut
    required this.createdAt,
  });

  /// Convertit le modèle User en dictionnaire pour stockage en BDD
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'passwordHash': passwordHash,
      'businessName': businessName,
      'criticalStockThreshold': criticalStockThreshold,
      'warningStockThreshold': warningStockThreshold,
      'warningColor': warningColor,
      'criticalColor': criticalColor,
      'createdAt': createdAt,
    };
  }

  /// Crée une instance de User à partir d'un dictionnaire (depuis BDD)
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      name: map['name'] as String,
      email: map['email'] as String,
      passwordHash: map['passwordHash'] as String,
      businessName: map['businessName'] as String,
      criticalStockThreshold: map['criticalStockThreshold'] as int? ?? 5,
      warningStockThreshold: map['warningStockThreshold'] as int? ?? 10,
      warningColor: map['warningColor'] as String? ?? '#FF9800',
      criticalColor: map['criticalColor'] as String? ?? '#F44336',
      createdAt: map['createdAt'] as String,
    );
  }
}
