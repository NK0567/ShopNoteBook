/// Modèle représentant un réapprovisionnement/achat de stock
/// Enregistre chaque achat de produits auprès des fournisseurs
class Purchase {
  // Identifiant unique du réapprovisionnement
  final int? id;
  
  // ID de l'utilisateur qui a enregistré le réapprovisionnement
  final int userId;
  
  // ID du produit réapprovisionné
  final int productId;
  
  // Nom du produit au moment de l'achat (snapshot pour historique)
  final String productName;
  
  // Quantité achetée dans cette transaction
  final int quantity;
  
  // Prix unitaire payé lors de l'achat
  final double unitCostPrice;
  
  // Coût total de l'achat (quantité * prix unitaire)
  final double totalCost;
  
  // Nom du fournisseur (source d'approvisionnement)
  final String supplier;
  
  // Numéro de bon de commande ou facture si disponible
  final String? invoiceNumber;
  
  // Date de l'achat/réapprovisionnement
  final String purchaseDate;
  
  // Notes optionnelles (ex: délai de livraison, conditions spéciales)
  final String? notes;

  /// Constructeur du modèle Purchase
  Purchase({
    this.id,
    required this.userId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCostPrice,
    required this.totalCost,
    required this.supplier,
    this.invoiceNumber,
    required this.purchaseDate,
    this.notes,
  });

  /// Convertit le modèle Purchase en dictionnaire pour stockage en BDD
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitCostPrice': unitCostPrice,
      'totalCost': totalCost,
      'supplier': supplier,
      'invoiceNumber': invoiceNumber,
      'purchaseDate': purchaseDate,
      'notes': notes,
    };
  }

  /// Crée une instance de Purchase à partir d'un dictionnaire (depuis BDD)
  factory Purchase.fromMap(Map<String, dynamic> map) {
    return Purchase(
      id: map['id'] as int?,
      userId: map['userId'] as int,
      productId: map['productId'] as int,
      productName: map['productName'] as String,
      quantity: map['quantity'] as int,
      unitCostPrice: (map['unitCostPrice'] as num).toDouble(),
      totalCost: (map['totalCost'] as num).toDouble(),
      supplier: map['supplier'] as String,
      invoiceNumber: map['invoiceNumber'] as String?,
      purchaseDate: map['purchaseDate'] as String,
      notes: map['notes'] as String?,
    );
  }
}
