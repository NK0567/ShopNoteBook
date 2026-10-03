/// Règles de calcul reprises des classeurs Excel (feuilles Inventaire / Sortie),
/// corrigées : stock jamais négatif, CUMP protégé contre la division par zéro,
/// bénéfice calculé sur le CUMP au moment de la vente.
library;

/// Niveau d'alerte d'un produit (statut de la feuille Inventaire).
enum StockStatus {
  /// Stock final <= 0.
  unavailable('Non disponible'),

  /// Stock final < 50 % du seuil d'alerte.
  urgent('Approvisionnement urgent'),

  /// Stock final < seuil d'alerte.
  needed('Approvisionnement nécessaire'),

  /// Stock final >= seuil d'alerte.
  ok('Niveau satisfaisant');

  const StockStatus(this.label);
  final String label;

  bool get isAlert => this != StockStatus.ok;

  /// Rouge pour "non disponible" et "urgent", orange pour "nécessaire".
  bool get isCritical => this == StockStatus.unavailable || this == StockStatus.urgent;
}

class StockMath {
  /// Stock final = stock initial + entrées - sorties.
  static int finalStock(int initialStock, int qtyIn, int qtyOut) =>
      initialStock + qtyIn - qtyOut;

  /// Coût unitaire moyen pondéré (CUMP) :
  /// (valeur du stock initial + total des entrées) / (stock initial + quantités entrées).
  static double cump({
    required int initialStock,
    required double initialUnitCost,
    required int qtyIn,
    required double valueIn,
  }) {
    final qty = initialStock + qtyIn;
    if (qty <= 0) return initialUnitCost;
    return (initialStock * initialUnitCost + valueIn) / qty;
  }

  static StockStatus status(int stock, int alertThreshold) {
    if (stock <= 0) return StockStatus.unavailable;
    if (stock < 0.5 * alertThreshold) return StockStatus.urgent;
    if (stock < alertThreshold) return StockStatus.needed;
    return StockStatus.ok;
  }

  /// Bénéfice d'une vente : (prix de vente - CUMP) x quantité.
  static double saleProfit(int quantity, double unitPrice, double unitCost) =>
      (unitPrice - unitCost) * quantity;

  /// Marge en % du prix de vente.
  static double marginRate(double unitPrice, double unitCost) =>
      unitPrice <= 0 ? 0 : (unitPrice - unitCost) / unitPrice * 100;
}
