import '../core/pricing.dart';
import '../core/stock_math.dart';

export '../core/pricing.dart' show PackMath, LevelPrice, PriceChoice, Pricing, Vat;
export 'shop_models.dart';

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

  /// Un code de secours existe (permet de réinitialiser un mot de passe oublié).
  final bool hasRecoveryCode;

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
    this.hasRecoveryCode = false,
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
    hasRecoveryCode: m['recoveryHash'] != null,
  );

  AppUser copyWith({
    String? name,
    String? businessName,
    int? defaultAlertThreshold,
    int? warningColor,
    int? criticalColor,
    int? autoLockMinutes,
  }) => AppUser(
    id: id,
    name: name ?? this.name,
    email: email,
    businessName: businessName ?? this.businessName,
    defaultAlertThreshold: defaultAlertThreshold ?? this.defaultAlertThreshold,
    warningColor: warningColor ?? this.warningColor,
    criticalColor: criticalColor ?? this.criticalColor,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    createdAt: createdAt,
    hasRecoveryCode: hasRecoveryCode,
  );
}

class Category {
  final int id;
  final String name;
  const Category({required this.id, required this.name});

  factory Category.fromMap(Map<String, Object?> m) => Category(id: m['id'] as int, name: m['name'] as String);
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
  /// Prix de vente de base (tarif « Détail »).
  final double sellingPrice;
  final bool archived;

  /// Code-barres (EAN…) : saisi à la douchette ou au clavier.
  final String? barcode;

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
    this.barcode,
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
    barcode: m['barcode'] as String?,
  );

  /// Référence normalisée : sans espaces superflus, en majuscules
  /// (évite les doublons "tc"/"TC" observés dans les classeurs).
  static String normalizeReference(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
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

  /// Pertes (casse, vol, périmés, écarts d'inventaire), valorisées au CUMP.
  final int qtyLoss;
  final double valueLoss;

  const StockItem({
    required this.product,
    required this.categoryName,
    required this.qtyIn,
    required this.valueIn,
    required this.qtyOut,
    required this.salesAmount,
    required this.profit,
    this.qtyLoss = 0,
    this.valueLoss = 0,
  });

  int get stock => StockMath.finalStock(product.initialStock, qtyIn, qtyOut, qtyLoss);

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
  entry('IN', 'Entrée', 'E'),
  sale('OUT', 'Vente', 'S'),
  loss('LOSS', 'Perte', 'P');

  const MovementType(this.code, this.label, this.prefix);
  final String code;
  final String label;

  /// Préfixe des numéros : E-0001, S-0001, P-0001.
  final String prefix;

  static MovementType fromCode(String code) => MovementType.values.firstWhere((t) => t.code == code);
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

  /// Ticket de caisse de la vente (null pour les entrées, pertes et anciennes ventes).
  final int? ticketId;
  final int? ticketNumber;

  /// Conditionnement utilisé à la saisie (ex. « Carton » de 24). La quantité
  /// et le prix restent toujours exprimés à l'unité de base.
  final String? packName;
  final int? packSize;

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
    this.ticketId,
    this.ticketNumber,
    this.packName,
    this.packSize,
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
    ticketId: m['ticketId'] as int?,
    ticketNumber: m['ticketNumber'] as int?,
    packName: m['packName'] as String?,
    packSize: m['packSize'] as int?,
  );

  double get total => quantity * unitPrice;

  /// « 2 Cartons (48 unités) » ou « 5 unités ».
  String get quantityLabel => PackMath.label(quantity, unit, packName, packSize);

  /// Prix affiché : par conditionnement si la ligne a été saisie ainsi.
  double get displayPrice => PackMath.isPack(packSize) && quantity % packSize! == 0 ? unitPrice * packSize! : unitPrice;

  double get profit => type == MovementType.sale ? StockMath.saleProfit(quantity, unitPrice, unitCost) : 0;

  /// Valeur d'une perte (au CUMP du moment).
  double get lossValue => type == MovementType.loss ? quantity * unitCost : 0;

  String get code => '${type.prefix}-${number.toString().padLeft(4, '0')}';
}

/// Agrégats d'une période (tableau de bord / rapports).
class PeriodSummary {
  final int qtyIn;
  final double valueIn;
  final int qtyOut;
  final double salesAmount;
  final double profit;
  final int salesCount;
  final int qtyLoss;
  final double valueLoss;

  /// Argent réellement encaissé sur la période (ventes comptant + remboursements de crédit).
  final double cashIn;

  const PeriodSummary({
    this.qtyIn = 0,
    this.valueIn = 0,
    this.qtyOut = 0,
    this.salesAmount = 0,
    this.profit = 0,
    this.salesCount = 0,
    this.qtyLoss = 0,
    this.valueLoss = 0,
    this.cashIn = 0,
  });

  double get marginRate => salesAmount <= 0 ? 0 : profit / salesAmount * 100;

  /// Bénéfice après déduction des pertes.
  double get netProfit => profit - valueLoss;
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

/// Ligne d'un panier de vente (avant enregistrement).
class SaleLine {
  final StockItem item;

  /// Quantité à l'unité de base (un carton de 24 = 24).
  final int quantity;

  /// Prix à l'unité de base.
  final double unitPrice;

  /// Conditionnement choisi à la saisie (null = vente à l'unité).
  final String? packName;
  final int? packSize;

  /// Tarif appliqué (« Détail », « Gros »…), pour information.
  final String? levelName;

  const SaleLine({
    required this.item,
    required this.quantity,
    required this.unitPrice,
    this.packName,
    this.packSize,
    this.levelName,
  });

  double get total => quantity * unitPrice;
  double get profit => StockMath.saleProfit(quantity, unitPrice, item.cump);

  String get quantityLabel => PackMath.label(quantity, item.product.unit, packName, packSize);

  /// Prix par conditionnement si la ligne est saisie en cartons, sinon à l'unité.
  double get displayPrice => PackMath.isPack(packSize) ? unitPrice * packSize! : unitPrice;

  String get priceUnitLabel => PackMath.isPack(packSize) ? packName! : item.product.unit;

  SaleLine copyWith({int? quantity, double? unitPrice}) => SaleLine(
    item: item,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    packName: packName,
    packSize: packSize,
    levelName: levelName,
  );
}

/// Modes d'encaissement proposés.
const paymentMethods = ['Espèces', 'Mobile Money', 'Orange Money', 'Virement', 'Autre'];

/// Encaissement rattaché à un ticket (paiement comptant, acompte ou remboursement de crédit).
class Payment {
  final int id;
  final int ticketId;
  final int ticketNumber;
  final double amount;
  final DateTime date;
  final String method;
  final String? note;
  final bool cancelled;

  /// Montant négatif : somme rendue au client après une annulation.
  bool get isRefund => amount < 0;

  const Payment({
    required this.id,
    required this.ticketId,
    required this.ticketNumber,
    required this.amount,
    required this.date,
    required this.method,
    this.note,
    this.cancelled = false,
  });

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
    id: m['id'] as int,
    ticketId: m['ticketId'] as int,
    ticketNumber: (m['ticketNumber'] as int?) ?? 0,
    amount: (m['amount'] as num).toDouble(),
    date: DateTime.parse(m['date'] as String),
    method: m['method'] as String,
    note: m['note'] as String?,
    cancelled: (m['cancelled'] as int) == 1,
  );
}

/// Ticket de caisse : une vente d'un ou plusieurs articles à un client.
class Ticket {
  final int id;
  final int number;
  final DateTime date;
  final String? client;
  final String? note;

  /// Total des lignes non annulées.
  final double total;

  /// Total encaissé (paiements non annulés).
  final double paid;
  final int lineCount;

  /// Facture émise pour ce ticket (numérotation annuelle continue, sans trou).
  final int? invoiceYear;
  final int? invoiceNumber;
  final DateTime? invoiceDate;

  const Ticket({
    required this.id,
    required this.number,
    required this.date,
    this.client,
    this.note,
    required this.total,
    required this.paid,
    required this.lineCount,
    this.invoiceYear,
    this.invoiceNumber,
    this.invoiceDate,
  });

  bool get hasInvoice => invoiceNumber != null;

  /// « FAC-2026-0001 ».
  String? get invoiceCode =>
      invoiceNumber == null ? null : 'FAC-$invoiceYear-${invoiceNumber.toString().padLeft(4, '0')}';

  factory Ticket.fromMap(Map<String, Object?> m) => Ticket(
    id: m['id'] as int,
    number: m['number'] as int,
    date: DateTime.parse(m['date'] as String),
    client: m['client'] as String?,
    note: m['note'] as String?,
    total: ((m['total'] as num?) ?? 0).toDouble(),
    paid: ((m['paid'] as num?) ?? 0).toDouble(),
    lineCount: ((m['lineCount'] as num?) ?? 0).toInt(),
    invoiceYear: m['invoiceYear'] as int?,
    invoiceNumber: m['invoiceNumber'] as int?,
    invoiceDate: m['invoiceDate'] == null ? null : DateTime.parse(m['invoiceDate'] as String),
  );

  /// Reste à payer (négatif = trop-perçu à rendre au client, après une annulation).
  double get balance => total - paid;

  bool get isCredit => balance >= 1;

  String get code => 'T-${number.toString().padLeft(4, '0')}';
}

/// Ticket avec ses lignes et ses encaissements (détail / reçu).
class TicketDetail {
  final Ticket ticket;
  final List<Movement> lines;
  final List<Payment> payments;

  const TicketDetail(this.ticket, this.lines, this.payments);
}

/// Total dû par un client (somme des tickets non soldés).
class ClientDebt {
  final String client;
  final double balance;
  final int ticketCount;
  final DateTime oldest;

  const ClientDebt({required this.client, required this.balance, required this.ticketCount, required this.oldest});
}
