import '../core/stock_math.dart';

/// Compte commerçant (une boutique par compte, données isolées par userId).
class AppUser {
  final int id;
  final String name;
  final String email;
  final String businessName;
  final int defaultAlertThreshold;
  final int warningColor;
  final int criticalColor;
  final int autoLockMinutes;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.businessName,
    required this.defaultAlertThreshold,
    required this.warningColor,
    required this.criticalColor,
    required this.autoLockMinutes,
    required this.createdAt,
  });

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        name: m['name'] as String,
        email: m['email'] as String,
        businessName: m['businessName'] as String,
        defaultAlertThreshold: m['defaultAlertThreshold'] as int,
        warningColor: m['warningColor'] as int,
        criticalColor: m['criticalColor'] as int,
        autoLockMinutes: m['autoLockMinutes'] as int,
        createdAt: DateTime.parse(m['createdAt'] as String),
      );

  AppUser copyWith({
    String? name,
    String? businessName,
    int? defaultAlertThreshold,
    int? warningColor,
    int? criticalColor,
    int? autoLockMinutes,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email,
        businessName: businessName ?? this.businessName,
        defaultAlertThreshold: defaultAlertThreshold ?? this.defaultAlertThreshold,
        warningColor: warningColor ?? this.warningColor,
        criticalColor: criticalColor ?? this.criticalColor,
        autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
        createdAt: createdAt,
      );
}

class Category {
  final int id;
  final String name;
  const Category({required this.id, required this.name});

  factory Category.fromMap(Map<String, Object?> m) =>
      Category(id: m['id'] as int, name: m['name'] as String);
}

/// Fiche produit (feuille "Marchandise").
class Product {
  final int? id;
  final String reference;
  final String name;
  final int? categoryId;
  final String unit;
  final int alertThreshold;
  final int initialStock;
  final double initialUnitCost;
  final double sellingPrice;
  final bool archived;

  const Product({
    this.id,
    required this.reference,
    required this.name,
    this.categoryId,
    required this.unit,
    required this.alertThreshold,
    required this.initialStock,
    required this.initialUnitCost,
    required this.sellingPrice,
    this.archived = false,
  });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int,
        reference: m['reference'] as String,
        name: m['name'] as String,
        categoryId: m['categoryId'] as int?,
        unit: m['unit'] as String,
        alertThreshold: m['alertThreshold'] as int,
        initialStock: m['initialStock'] as int,
        initialUnitCost: (m['initialUnitCost'] as num).toDouble(),
        sellingPrice: (m['sellingPrice'] as num).toDouble(),
        archived: (m['archived'] as int) == 1,
      );

  /// Référence normalisée : sans espaces superflus, en majuscules
  /// (évite les doublons "tc"/"TC" observés dans les classeurs).
  static String normalizeReference(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
}

/// Ligne d'inventaire calculée (feuille "Inventaire") : jamais stockée,
/// toujours recalculée depuis le journal des mouvements.
class StockItem {
  final Product product;
  final String? categoryName;
  final int qtyIn;
  final double valueIn;
  final int qtyOut;
  final double salesAmount;
  final double profit;

  const StockItem({
    required this.product,
    required this.categoryName,
    required this.qtyIn,
    required this.valueIn,
    required this.qtyOut,
    required this.salesAmount,
    required this.profit,
  });

  int get stock => StockMath.finalStock(product.initialStock, qtyIn, qtyOut);

  double get cump => StockMath.cump(
        initialStock: product.initialStock,
        initialUnitCost: product.initialUnitCost,
        qtyIn: qtyIn,
        valueIn: valueIn,
      );

  double get stockValue => stock <= 0 ? 0 : stock * cump;

  StockStatus get status => StockMath.status(stock, product.alertThreshold);

  /// Quantité suggérée pour revenir au double du seuil d'alerte.
  int get suggestedReorder {
    final target = product.alertThreshold * 2;
    return stock >= target ? 0 : target - (stock < 0 ? 0 : stock);
  }
}

enum MovementType {
  entry('IN', 'Entrée'),
  sale('OUT', 'Sortie');

  const MovementType(this.code, this.label);
  final String code;
  final String label;

  static MovementType fromCode(String code) =>
      MovementType.values.firstWhere((t) => t.code == code);
}

/// Mouvement de stock (feuilles "Entrée" et "Sortie").
/// Un mouvement n'est jamais supprimé : il peut seulement être annulé (avec motif).
class Movement {
  final int id;
  final int number;
  final MovementType type;
  final int productId;
  final String productReference;
  final String productName;
  final String? categoryName;
  final String unit;
  final DateTime date;
  final int quantity;
  final double unitPrice;
  final double unitCost;
  final String? partner;
  final String? note;
  final bool cancelled;
  final String? cancelReason;
  final DateTime? cancelledAt;

  const Movement({
    required this.id,
    required this.number,
    required this.type,
    required this.productId,
    required this.productReference,
    required this.productName,
    required this.categoryName,
    required this.unit,
    required this.date,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    this.partner,
    this.note,
    this.cancelled = false,
    this.cancelReason,
    this.cancelledAt,
  });

  factory Movement.fromMap(Map<String, Object?> m) => Movement(
        id: m['id'] as int,
        number: m['number'] as int,
        type: MovementType.fromCode(m['type'] as String),
        productId: m['productId'] as int,
        productReference: m['reference'] as String,
        productName: m['productName'] as String,
        categoryName: m['categoryName'] as String?,
        unit: m['unit'] as String,
        date: DateTime.parse(m['date'] as String),
        quantity: m['quantity'] as int,
        unitPrice: (m['unitPrice'] as num).toDouble(),
        unitCost: (m['unitCost'] as num).toDouble(),
        partner: m['partner'] as String?,
        note: m['note'] as String?,
        cancelled: (m['cancelled'] as int) == 1,
        cancelReason: m['cancelReason'] as String?,
        cancelledAt: m['cancelledAt'] == null ? null : DateTime.parse(m['cancelledAt'] as String),
      );

  double get total => quantity * unitPrice;

  double get profit =>
      type == MovementType.sale ? StockMath.saleProfit(quantity, unitPrice, unitCost) : 0;

  String get code => '${type == MovementType.entry ? 'E' : 'S'}-${number.toString().padLeft(4, '0')}';
}

/// Agrégats d'une période (tableau de bord / rapports).
class PeriodSummary {
  final int qtyIn;
  final double valueIn;
  final int qtyOut;
  final double salesAmount;
  final double profit;
  final int salesCount;

  const PeriodSummary({
    this.qtyIn = 0,
    this.valueIn = 0,
    this.qtyOut = 0,
    this.salesAmount = 0,
    this.profit = 0,
    this.salesCount = 0,
  });

  double get marginRate => salesAmount <= 0 ? 0 : profit / salesAmount * 100;
}

/// Classement des ventes par produit.
class ProductRanking {
  final int productId;
  final String reference;
  final String name;
  final int quantity;
  final double amount;
  final double profit;

  const ProductRanking({
    required this.productId,
    required this.reference,
    required this.name,
    required this.quantity,
    required this.amount,
    required this.profit,
  });
}

/// Valeur agrégée par catégorie (graphiques en secteurs du tableau de bord).
class CategoryShare {
  final String category;
  final double value;
  const CategoryShare(this.category, this.value);
}

class AuditEntry {
  final DateTime date;
  final String action;
  final String details;
  const AuditEntry(this.date, this.action, this.details);
}
