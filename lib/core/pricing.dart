import 'format.dart';

/// Conditionnements : la quantité est toujours stockée à l'unité de base
/// (bouteille, pièce, kg…) ; un carton de 24 n'est qu'une façon de la saisir.
class PackMath {
  static bool isPack(int? packSize) => packSize != null && packSize > 1;

  /// « 2 Cartons (48 bouteilles) », « 1 Carton + 5 bouteilles », « 7 bouteilles ».
  static String label(int quantity, String unit, String? packName, int? packSize) {
    if (!isPack(packSize) || packName == null || quantity < packSize!) return Fmt.qtyUnit(quantity, unit);
    final packs = quantity ~/ packSize;
    final rest = quantity % packSize;
    final head = Fmt.qtyUnit(packs, packName);
    return rest == 0 ? '$head (${Fmt.qtyUnit(quantity, unit)})' : '$head + ${Fmt.qtyUnit(rest, unit)}';
  }

  /// Stock exprimé en conditionnement : « 12 Cartons + 3 bouteilles ».
  static String stockLabel(int stock, String unit, String? packName, int? packSize) {
    if (!isPack(packSize) || packName == null || stock < packSize!) return Fmt.qtyUnit(stock, unit);
    final packs = stock ~/ packSize;
    final rest = stock % packSize;
    final head = Fmt.qtyUnit(packs, packName);
    return rest == 0 ? head : '$head + ${Fmt.qtyUnit(rest, unit)}';
  }
}

/// Prix d'un tarif pour un produit : [price] à l'unité de base, appliqué
/// automatiquement à partir de [minQty] unités (0 = seulement si choisi).
class LevelPrice {
  final int levelId;
  final String levelName;
  final int minQty;
  final double price;
  const LevelPrice({required this.levelId, required this.levelName, required this.minQty, required this.price});
}

class PriceChoice {
  final double unitPrice;

  /// Nom du tarif appliqué (« Détail », « Gros »…).
  final String levelName;
  const PriceChoice(this.unitPrice, this.levelName);
}

/// Choix automatique du prix de vente.
///
/// Règles (toutes paramétrables par le commerçant, rien n'est figé) :
/// 1. prix de base = tarif « Détail » du produit ;
/// 2. si un tarif est choisi pour la vente (ou attitré au client), il remplace le prix de base ;
/// 3. les tarifs à palier (« Gros dès 12 unités ») s'appliquent d'office quand la
///    quantité est atteinte ;
/// 4. le client paie toujours le prix le plus avantageux parmi ceux qui s'appliquent.
/// Le vendeur peut ensuite modifier le prix à la main.
class Pricing {
  static const retailName = 'Détail';

  static PriceChoice resolve({
    required double basePrice,
    required List<LevelPrice> levels,
    int? chosenLevelId,
    required int quantity,
  }) {
    var best = PriceChoice(basePrice, retailName);
    if (chosenLevelId != null) {
      final chosen = levels.where((l) => l.levelId == chosenLevelId && l.price > 0).firstOrNull;
      if (chosen != null) best = PriceChoice(chosen.price, chosen.levelName);
    }
    for (final l in levels) {
      if (l.minQty > 0 && quantity >= l.minQty && l.price > 0 && l.price < best.unitPrice) {
        best = PriceChoice(l.price, l.levelName);
      }
    }
    return best;
  }

  /// Prix d'un conditionnement : son prix fixé, sinon le prix unitaire x contenance.
  static double packPrice({required double fixedPackPrice, required int packSize, required double unitPrice}) =>
      fixedPackPrice > 0 ? fixedPackPrice : unitPrice * packSize;
}

/// TVA : les prix saisis sont TTC (habitude des boutiques) ; la facture
/// détaille HT / TVA / TTC quand la boutique est assujettie.
class Vat {
  /// Taux usuel au Cameroun : 17,5 % + 10 % de centimes additionnels communaux = 19,25 %.
  static const defaultRate = 19.25;

  static double excludingTax(double ttc, double rate) => ttc / (1 + rate / 100);

  static double taxPart(double ttc, double rate) => ttc - excludingTax(ttc, rate);
}
