/// Modèle représentant une transaction de vente
/// Enregistre chaque vente effectuée avec tous ses détails
class Sale {
  // Identifiant unique de la vente
  final int? id;
  
  // ID de l'utilisateur qui a effectué la vente
  final int userId;
  
  // ID du produit vendu
  final int productId;
  
  // Nom du produit au moment de la vente (snapshot pour historique)
  final String productName;
  
  // Quantité vendue lors de cette transaction
  final int quantity;
  
  // Prix unitaire auquel le produit a été vendu
  final double unitPrice;
  
  // Montant total de la vente (quantité * prix unitaire)
  final double totalAmount;
  
  // Bénéfice généré sur cette vente (total - (coût unitaire * quantité))
  final double profit;
  
  // Date et heure précise de la vente
  final String saleDate;
  
  // Notes ou commentaires optionnels sur la transaction (ex: client particulier)
  final String? notes;

  /// Constructeur du modèle Sale
  Sale({
    this.id,
    required this.userId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    required this.profit,
    required this.saleDate,
    this.notes,
  });

  /// Convertit le modèle Sale en dictionnaire pour stockage en BDD
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'profit': profit,
      'saleDate': saleDate,
      'notes': notes,
    };
  }

  /// Crée une instance de Sale à partir d'un dictionnaire (depuis BDD)
  factory Sale.fromMap(Map<String, dynamic> map) {
    return Sale(
      id: map['id'] as int?,
      userId: map['userId'] as int,
      productId: map['productId'] as int,
      productName: map['productName'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unitPrice'] as num).toDouble(),
      totalAmount: (map['totalAmount'] as num).toDouble(),
      profit: (map['profit'] as num).toDouble(),
      saleDate: map['saleDate'] as String,
      notes: map['notes'] as String?,
    );
  }
}
