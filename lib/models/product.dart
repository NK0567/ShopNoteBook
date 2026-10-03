/// Modèle représentant un produit du catalogue
/// Gère tous les informations relatives à un article en stock
class Product {
  // Identifiant unique du produit
  final int? id;
  
  // ID de l'utilisateur propriétaire du produit (sécurité et confidentialité)
  final int userId;
  
  // Nom du produit (ex: "Riz blanc 25kg", "Sucre cristallisé")
  final String name;
  
  // Description détaillée du produit
  final String description;
  
  // Prix d'achat unitaire (fixe, ne peut pas être modifié après enregistrement)
  final double costPrice;
  
  // Prix de vente unitaire (modifiable selon les stratégies commerciales)
  final double sellingPrice;
  
  // Quantité actuellement en stock
  final int quantity;
  
  // Quantité totale de fois que le produit a été vendu
  final int totalSoldQuantity;
  
  // Seuil minimum de stock avant alerte orange (réapprov recommandée)
  final int lowStockThreshold;
  
  // Seuil critique de stock avant alerte rouge (réapprov urgente)
  final int criticalStockThreshold;
  
  // Code de catégorie ou famille de produit
  final String category;
  
  // Unité de mesure (kg, pièce, litre, etc.)
  final String unit;
  
  // Date d'ajout du produit au catalogue
  final String createdAt;
  
  // Date de dernière modification
  final String updatedAt;

  /// Constructeur du modèle Product
  Product({
    this.id,
    required this.userId,
    required this.name,
    required this.description,
    required this.costPrice,
    required this.sellingPrice,
    required this.quantity,
    this.totalSoldQuantity = 0,
    required this.lowStockThreshold,
    required this.criticalStockThreshold,
    required this.category,
    required this.unit,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Calcule le bénéfice potentiel unitaire (prix vente - prix achat)
  double get potentialProfit {
    return sellingPrice - costPrice;
  }

  /// Calcule la marge bénéficiaire en pourcentage
  double get profitMargin {
    if (costPrice == 0) return 0;
    return (potentialProfit / costPrice) * 100;
  }

  /// Détermine l'état du stock basé sur les seuils critiques
  /// Retourne: "ok" (vert), "warning" (orange), ou "critical" (rouge)
  String getStockStatus() {
    if (quantity <= criticalStockThreshold) {
      return 'critical'; // Stock critique (alerte rouge)
    } else if (quantity <= lowStockThreshold) {
      return 'warning'; // Stock faible (alerte orange)
    }
    return 'ok'; // Stock suffisant (vert)
  }

  /// Vérifie si le produit est en rupture de stock
  bool get isOutOfStock {
    return quantity <= 0;
  }

  /// Convertit le modèle Product en dictionnaire pour stockage en BDD
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'description': description,
      'costPrice': costPrice,
      'sellingPrice': sellingPrice,
      'quantity': quantity,
      'totalSoldQuantity': totalSoldQuantity,
      'lowStockThreshold': lowStockThreshold,
      'criticalStockThreshold': criticalStockThreshold,
      'category': category,
      'unit': unit,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Crée une instance de Product à partir d'un dictionnaire (depuis BDD)
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      userId: map['userId'] as int,
      name: map['name'] as String,
      description: map['description'] as String,
      costPrice: (map['costPrice'] as num).toDouble(),
      sellingPrice: (map['sellingPrice'] as num).toDouble(),
      quantity: map['quantity'] as int,
      totalSoldQuantity: map['totalSoldQuantity'] as int? ?? 0,
      lowStockThreshold: map['lowStockThreshold'] as int,
      criticalStockThreshold: map['criticalStockThreshold'] as int,
      category: map['category'] as String,
      unit: map['unit'] as String,
      createdAt: map['createdAt'] as String,
      updatedAt: map['updatedAt'] as String,
    );
  }

  /// Crée une copie du produit avec certains champs modifiés
  Product copyWith({
    int? id,
    int? userId,
    String? name,
    String? description,
    double? costPrice,
    double? sellingPrice,
    int? quantity,
    int? totalSoldQuantity,
    int? lowStockThreshold,
    int? criticalStockThreshold,
    String? category,
    String? unit,
    String? createdAt,
    String? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      quantity: quantity ?? this.quantity,
      totalSoldQuantity: totalSoldQuantity ?? this.totalSoldQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      criticalStockThreshold: criticalStockThreshold ?? this.criticalStockThreshold,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
