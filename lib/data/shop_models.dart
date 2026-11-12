import '../core/pricing.dart';

// ==========================================================================
// v4 : boutique paramétrable (détaillant, grossiste ou les deux)
// ==========================================================================

/// Type de commerce : ne fait que proposer des réglages de départ.
/// Tout reste modifiable ensuite (tarifs, conditionnements, documents).
enum ShopType {
  retail('retail', 'Détaillant', 'Vente à l\'unité aux particuliers'),
  wholesale('wholesale', 'Grossiste', 'Vente par cartons, sacs, palettes aux revendeurs'),
  hybrid('hybrid', 'Détail et gros', 'Prix détail, demi-gros et gros selon le client ou la quantité');

  const ShopType(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  static ShopType fromCode(String? code) => ShopType.values.firstWhere((t) => t.code == code, orElse: () => retail);
}

/// Coordonnées et réglages de facturation de la boutique.
class ShopProfile {
  final ShopType shopType;
  final String? activity;
  final String? address;
  final String? city;
  final String? phone;

  /// Numéro d'Identifiant Unique (impôts).
  final String? niu;

  /// Registre du Commerce et du Crédit Mobilier.
  final String? rccm;
  final String? invoiceFooter;
  final bool vatEnabled;
  final double vatRate;

  /// Largeur du papier de l'imprimante de tickets (58 ou 80 mm).
  final int receiptWidth;

  const ShopProfile({
    this.shopType = ShopType.retail,
    this.activity,
    this.address,
    this.city,
    this.phone,
    this.niu,
    this.rccm,
    this.invoiceFooter,
    this.vatEnabled = false,
    this.vatRate = Vat.defaultRate,
    this.receiptWidth = 80,
  });

  factory ShopProfile.fromMap(Map<String, Object?> m) => ShopProfile(
    shopType: ShopType.fromCode(m['shopType'] as String?),
    activity: m['activity'] as String?,
    address: m['address'] as String?,
    city: m['city'] as String?,
    phone: m['phone'] as String?,
    niu: m['niu'] as String?,
    rccm: m['rccm'] as String?,
    invoiceFooter: m['invoiceFooter'] as String?,
    vatEnabled: (m['vatEnabled'] as int? ?? 0) == 1,
    vatRate: ((m['vatRate'] as num?) ?? Vat.defaultRate).toDouble(),
    receiptWidth: (m['receiptWidth'] as int?) ?? 80,
  );

  Map<String, Object?> toMap() => {
    'shopType': shopType.code,
    'activity': activity,
    'address': address,
    'city': city,
    'phone': phone,
    'niu': niu,
    'rccm': rccm,
    'invoiceFooter': invoiceFooter,
    'vatEnabled': vatEnabled ? 1 : 0,
    'vatRate': vatRate,
    'receiptWidth': receiptWidth,
  };

  /// Lignes d'en-tête des documents (activité, adresse, téléphone, NIU, RCCM).
  List<String> get headerLines => [
    if ((activity ?? '').isNotEmpty) activity!,
    [address, city].where((s) => (s ?? '').isNotEmpty).join(', '),
    if ((phone ?? '').isNotEmpty) 'Tél. $phone',
    [
      if ((niu ?? '').isNotEmpty) 'NIU : $niu',
      if ((rccm ?? '').isNotEmpty) 'RCCM : $rccm',
    ].join('  ·  '),
  ].where((s) => s.isNotEmpty).toList();

  bool get isComplete => (address ?? '').isNotEmpty && (phone ?? '').isNotEmpty;
}

/// Tarif (grille de prix) : « Demi-gros », « Gros », « Revendeur »…
/// Le tarif « Détail » est le prix de vente de base de chaque produit.
class PriceLevel {
  final int id;
  final String name;

  /// Palier proposé par défaut pour les nouveaux produits (0 = seulement si choisi).
  /// Chaque produit a ensuite son propre palier (un carton de 12 ≠ un sac de 50).
  final int minQty;
  final int position;

  const PriceLevel({required this.id, required this.name, this.minQty = 0, this.position = 0});

  factory PriceLevel.fromMap(Map<String, Object?> m) => PriceLevel(
    id: m['id'] as int,
    name: m['name'] as String,
    minQty: m['minQty'] as int,
    position: m['position'] as int,
  );
}

/// Conditionnement d'un produit : carton de 24, sac de 50 kg, paquet de 10…
class ProductPack {
  final int? id;
  final String name;
  final int quantity;

  /// Prix de vente du conditionnement (0 = prix unitaire x quantité).
  final double price;
  final String? barcode;

  const ProductPack({this.id, required this.name, required this.quantity, this.price = 0, this.barcode});

  factory ProductPack.fromMap(Map<String, Object?> m) => ProductPack(
    id: m['id'] as int,
    name: m['name'] as String,
    quantity: m['quantity'] as int,
    price: (m['price'] as num).toDouble(),
    barcode: m['barcode'] as String?,
  );
}

/// Tarifs et conditionnements d'un produit.
class ProductPricing {
  /// Prix par tarif (id du tarif → prix à l'unité de base).
  final Map<int, double> levelPrices;

  /// Palier par tarif (id du tarif → quantité à partir de laquelle il s'applique seul ; 0 = jamais).
  final Map<int, int> levelMinQty;
  final List<ProductPack> packs;

  const ProductPricing({this.levelPrices = const {}, this.levelMinQty = const {}, this.packs = const []});

  static const empty = ProductPricing();

  List<LevelPrice> levelsFor(List<PriceLevel> levels) => [
    for (final l in levels)
      if ((levelPrices[l.id] ?? 0) > 0)
        LevelPrice(levelId: l.id, levelName: l.name, minQty: levelMinQty[l.id] ?? 0, price: levelPrices[l.id]!),
  ];

  /// Conditionnement principal (le plus grand), pour afficher le stock en cartons.
  ProductPack? get mainPack => packs.isEmpty ? null : (List.of(packs)..sort((a, b) => b.quantity - a.quantity)).first;
}

/// Fiche client.
class Client {
  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String? niu;

  /// Tarif attitré (ex. un revendeur paie toujours le prix « Gros »).
  final int? priceLevelId;

  /// Plafond de crédit (0 = pas de plafond).
  final double creditLimit;
  final String? note;

  /// Calculé : reste dû sur l'ensemble de ses tickets.
  final double balance;

  const Client({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.niu,
    this.priceLevelId,
    this.creditLimit = 0,
    this.note,
    this.balance = 0,
  });

  factory Client.fromMap(Map<String, Object?> m) => Client(
    id: m['id'] as int,
    name: m['name'] as String,
    phone: m['phone'] as String?,
    address: m['address'] as String?,
    niu: m['niu'] as String?,
    priceLevelId: m['priceLevelId'] as int?,
    creditLimit: ((m['creditLimit'] as num?) ?? 0).toDouble(),
    note: m['note'] as String?,
    balance: ((m['balance'] as num?) ?? 0).toDouble(),
  );
}

enum QuoteStatus {
  open('open', 'En attente'),
  converted('converted', 'Transformé en vente'),
  cancelled('cancelled', 'Annulé');

  const QuoteStatus(this.code, this.label);
  final String code;
  final String label;

  static QuoteStatus fromCode(String code) => QuoteStatus.values.firstWhere((s) => s.code == code);
}

class QuoteLine {
  final int productId;
  final String reference;
  final String productName;
  final String unit;
  final int quantity;
  final double unitPrice;
  final String? packName;
  final int? packSize;

  const QuoteLine({
    required this.productId,
    required this.reference,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    this.packName,
    this.packSize,
  });

  factory QuoteLine.fromMap(Map<String, Object?> m) => QuoteLine(
    productId: m['productId'] as int,
    reference: m['reference'] as String,
    productName: m['productName'] as String,
    unit: m['unit'] as String,
    quantity: m['quantity'] as int,
    unitPrice: (m['unitPrice'] as num).toDouble(),
    packName: m['packName'] as String?,
    packSize: m['packSize'] as int?,
  );

  double get total => quantity * unitPrice;
  String get quantityLabel => PackMath.label(quantity, unit, packName, packSize);
  double get displayPrice => PackMath.isPack(packSize) ? unitPrice * packSize! : unitPrice;
  String get priceUnitLabel => PackMath.isPack(packSize) ? packName! : unit;
}

/// Devis / facture pro forma : aucun effet sur le stock tant qu'il
/// n'est pas transformé en vente.
class Quote {
  final int id;
  final int number;
  final DateTime date;
  final DateTime? validUntil;
  final String? client;
  final String? note;
  final QuoteStatus status;
  final int? ticketId;
  final List<QuoteLine> lines;

  const Quote({
    required this.id,
    required this.number,
    required this.date,
    this.validUntil,
    this.client,
    this.note,
    required this.status,
    this.ticketId,
    this.lines = const [],
  });

  factory Quote.fromMap(Map<String, Object?> m, [List<QuoteLine> lines = const []]) => Quote(
    id: m['id'] as int,
    number: m['number'] as int,
    date: DateTime.parse(m['date'] as String),
    validUntil: m['validUntil'] == null ? null : DateTime.parse(m['validUntil'] as String),
    client: m['client'] as String?,
    note: m['note'] as String?,
    status: QuoteStatus.fromCode(m['status'] as String),
    ticketId: m['ticketId'] as int?,
    lines: lines,
  );

  double get total => lines.fold(0, (s, l) => s + l.total);

  String get code => 'DEV-${number.toString().padLeft(4, '0')}';

  bool isExpired(DateTime now) => validUntil != null && now.isAfter(validUntil!.add(const Duration(days: 1)));
}
