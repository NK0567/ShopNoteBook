import 'package:flutter_test/flutter_test.dart';
import 'package:shopnotbook/core/amount_words.dart';
import 'package:shopnotbook/data/app_database.dart';
import 'package:shopnotbook/data/models.dart';
import 'package:shopnotbook/data/shop_repository.dart';
import 'package:shopnotbook/services/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// Boutique paramétrable (schéma v4) : tarifs, paliers, conditionnements,
/// codes-barres, clients, factures numérotées, devis.
void main() {
  group('Montant en lettres', () {
    final cases = {
      0: 'zéro',
      1: 'un',
      17: 'dix-sept',
      21: 'vingt et un',
      71: 'soixante et onze',
      80: 'quatre-vingts',
      81: 'quatre-vingt-un',
      99: 'quatre-vingt-dix-neuf',
      100: 'cent',
      200: 'deux cents',
      201: 'deux cent un',
      1000: 'mille',
      1500: 'mille cinq cents',
      80000: 'quatre-vingt mille',
      200000: 'deux cent mille',
      1000000: 'un million',
      2500000: 'deux millions cinq cent mille',
      125750: 'cent vingt-cinq mille sept cent cinquante',
    };
    for (final e in cases.entries) {
      test('${e.key}', () => expect(AmountWords.integer(e.key), e.value));
    }
    test('francs', () {
      expect(AmountWords.francs(1), 'Un franc CFA');
      expect(AmountWords.francs(15000), 'Quinze mille francs CFA');
    });
  });

  group('Calcul des prix', () {
    const levels = [
      LevelPrice(levelId: 1, levelName: 'Demi-gros', minQty: 6, price: 900),
      LevelPrice(levelId: 2, levelName: 'Gros', minQty: 12, price: 800),
      LevelPrice(levelId: 3, levelName: 'Revendeur', minQty: 0, price: 850),
    ];
    test('prix de base sous les paliers', () {
      final c = Pricing.resolve(basePrice: 1000, levels: levels, quantity: 2);
      expect((c.unitPrice, c.levelName), (1000.0, 'Détail'));
    });
    test('palier atteint automatiquement', () {
      expect(Pricing.resolve(basePrice: 1000, levels: levels, quantity: 6).unitPrice, 900);
      expect(Pricing.resolve(basePrice: 1000, levels: levels, quantity: 24).levelName, 'Gros');
    });
    test('tarif attitré, mais le palier plus avantageux l\'emporte', () {
      expect(Pricing.resolve(basePrice: 1000, levels: levels, chosenLevelId: 3, quantity: 1).unitPrice, 850);
      expect(Pricing.resolve(basePrice: 1000, levels: levels, chosenLevelId: 3, quantity: 12).unitPrice, 800);
    });
    test('libellés de conditionnement', () {
      expect(PackMath.label(48, 'bouteille', 'Carton', 24), '2 Cartons (48 bouteilles)');
      expect(PackMath.label(29, 'bouteille', 'Carton', 24), '1 Carton + 5 bouteilles');
      expect(PackMath.label(5, 'bouteille', 'Carton', 24), '5 bouteilles');
      expect(PackMath.stockLabel(51, 'bouteille', 'Carton', 24), '2 Cartons + 3 bouteilles');
    });
    test('TVA incluse', () {
      expect(Vat.excludingTax(11925, 19.25), closeTo(10000, 0.01));
      expect(Vat.taxPart(11925, 19.25), closeTo(1925, 0.01));
    });
  });

  group('Base v4', () {
    late Database db;
    late ShopRepository repo;
    late Session session;
    late int uid;

    setUp(() async {
      db = await AppDatabase.open(factory: testDatabaseFactory(), path: inMemoryDatabasePath);
      repo = ShopRepository(db);
      session = Session(repo, hashIterations: 1000);
      await session.register(name: 'Awa', email: 'awa@test.cm', password: 'Boutique2026', businessName: 'Chez Awa');
      await session.login('awa@test.cm', 'Boutique2026');
      uid = session.userId;
    });

    tearDown(() => db.close());

    Future<StockItem> product(String ref, {int stock = 100, double cost = 500, double price = 800, String? barcode}) async {
      final id = await repo.saveProduct(
        uid,
        Product(
          reference: ref,
          name: 'Produit $ref',
          unit: 'bouteille',
          alertThreshold: 2,
          initialStock: stock,
          initialUnitCost: cost,
          sellingPrice: price,
          barcode: barcode,
        ),
      );
      return (await repo.stockItem(uid, id))!;
    }

    test('profil et préréglage « Détail et gros »', () async {
      expect((await repo.shopProfile(uid)).shopType, ShopType.retail);
      await repo.saveShopProfile(
        uid,
        const ShopProfile(shopType: ShopType.hybrid, address: 'Marché Mokolo', phone: '699 00 00 00', niu: 'm0123'),
      );
      final p = await repo.shopProfile(uid);
      expect(p.shopType, ShopType.hybrid);
      expect(p.niu, 'M0123');
      expect((await repo.priceLevels(uid)).map((l) => l.name), ['Demi-gros', 'Gros']);
      // Re-enregistrer ne duplique rien.
      await repo.saveShopProfile(uid, const ShopProfile(shopType: ShopType.wholesale));
      await repo.saveShopProfile(uid, const ShopProfile(shopType: ShopType.hybrid));
      expect((await repo.priceLevels(uid)).length, 2);
    });

    test('tarifs, conditionnements et code-barres', () async {
      final a = await product('BIERE', barcode: '6001234');
      final gros = await repo.savePriceLevel(uid, name: 'Gros', minQty: 24);
      expect(() => repo.savePriceLevel(uid, name: 'détail'), throwsA(isA<BusinessException>()));
      await repo.saveProductPricing(
        uid,
        a.product.id!,
        levelPrices: {gros: (price: 700, minQty: 24)},
        packs: const [ProductPack(name: 'Casier', quantity: 12, price: 9000, barcode: '6001235')],
      );
      final pr = await repo.productPricing(a.product.id!);
      expect(pr.levelPrices[gros], 700);
      expect(pr.levelMinQty[gros], 24);
      expect(pr.packs.single.name, 'Casier');
      expect((await repo.findByBarcode(uid, '6001234'))!.pack, isNull);
      expect((await repo.findByBarcode(uid, '6001235'))!.pack!.quantity, 12);
      // Un code-barres ne peut servir qu'à un seul produit.
      final b = await product('JUS');
      await expectLater(
        repo.saveProduct(uid, Product(reference: 'JUS', name: 'Jus', unit: 'u', alertThreshold: 1, initialStock: 0,
            initialUnitCost: 0, sellingPrice: 1, barcode: '6001235', id: b.product.id)),
        throwsA(isA<BusinessException>()),
      );
    });

    test('vente en cartons : stock et prix à l\'unité de base', () async {
      final a = await product('EAU', stock: 50, cost: 200, price: 300);
      final d = await repo.recordSale(
        userId: uid,
        lines: [SaleLine(item: a, quantity: 24, unitPrice: 6000 / 24, packName: 'Carton', packSize: 24)],
        date: DateTime.now(),
        paid: 6000,
      );
      expect(d.ticket.total, closeTo(6000, 0.001));
      expect(d.lines.single.quantityLabel, '1 Carton (24 bouteilles)');
      expect(d.lines.single.displayPrice, closeTo(6000, 0.001));
      expect((await repo.stockItem(uid, a.product.id!))!.stock, 26);
    });

    test('fiche client créée à la vente et plafond de crédit', () async {
      final a = await product('A');
      await repo.recordSale(userId: uid, lines: [SaleLine(item: a, quantity: 1, unitPrice: 800)], date: DateTime.now(), client: 'Mama Rose', paid: 0);
      final c = (await repo.clientByName(uid, 'mama rose'))!;
      expect(c.balance, 800);
      await repo.saveClient(uid, Client(id: c.id, name: 'Mama Rose', phone: '677', creditLimit: 1000));
      await expectLater(
        repo.recordSale(userId: uid, lines: [SaleLine(item: a, quantity: 1, unitPrice: 800)], date: DateTime.now(), client: 'Mama Rose', paid: 0),
        throwsA(isA<BusinessException>()),
      );
      // Paiement comptant : pas de crédit, pas de blocage.
      await repo.recordSale(userId: uid, lines: [SaleLine(item: a, quantity: 1, unitPrice: 800)], date: DateTime.now(), client: 'Mama Rose', paid: 800);
      // Renommer la fiche renomme l'historique.
      await repo.saveClient(uid, Client(id: c.id, name: 'Rose Ngo', creditLimit: 1000));
      expect((await repo.openTickets(uid, client: 'Rose Ngo')).length, 1);
      await expectLater(repo.deleteClient(uid, c.id!), throwsA(isA<BusinessException>()));
    });

    test('factures numérotées par année, sans trou ni doublon', () async {
      final a = await product('A');
      Future<int> sale() async => (await repo.recordSale(
            userId: uid,
            lines: [SaleLine(item: a, quantity: 1, unitPrice: 800)],
            date: DateTime.now(),
            paid: 800,
          )).ticket.id;
      final t1 = await sale(), t2 = await sale();
      final f1 = await repo.issueInvoice(uid, t1, date: DateTime(2026, 12, 31));
      expect(f1.invoiceCode, 'FAC-2026-0001');
      expect((await repo.issueInvoice(uid, t1)).invoiceCode, 'FAC-2026-0001'); // pas de nouveau numéro
      final f2 = await repo.issueInvoice(uid, t2, date: DateTime(2027, 1, 2));
      expect(f2.invoiceCode, 'FAC-2027-0001');
    });

    test('devis puis transformation en vente', () async {
      final a = await product('A', stock: 5);
      final q = await repo.createQuote(
        userId: uid,
        lines: [SaleLine(item: a, quantity: 3, unitPrice: 750)],
        date: DateTime.now(),
        validUntil: DateTime.now().add(const Duration(days: 15)),
        client: 'Ets Fotso',
      );
      expect(q.code, 'DEV-0001');
      expect(q.total, 2250);
      // Le devis ne touche pas au stock.
      expect((await repo.stockItem(uid, a.product.id!))!.stock, 5);
      final d = await repo.recordSale(
        userId: uid,
        lines: [SaleLine(item: a, quantity: 3, unitPrice: 750)],
        date: DateTime.now(),
        client: 'Ets Fotso',
        paid: 2250,
        quoteId: q.id,
      );
      final after = (await repo.quote(uid, q.id))!;
      expect(after.status, QuoteStatus.converted);
      expect(after.ticketId, d.ticket.id);
      await expectLater(repo.cancelQuote(uid, q.id), throwsA(isA<BusinessException>()));
    });

    test('sauvegarde v2 : tarifs, clients, devis restaurés', () async {
      final a = await product('A', barcode: '111');
      final gros = await repo.savePriceLevel(uid, name: 'Gros');
      await repo.saveProductPricing(
        uid,
        a.product.id!,
        levelPrices: {gros: (price: 600, minQty: 10)},
        packs: const [ProductPack(name: 'Carton', quantity: 10)],
      );
      await repo.saveClient(uid, Client(name: 'Ets Fotso', priceLevelId: gros, creditLimit: 50000));
      await repo.saveShopProfile(uid, const ShopProfile(shopType: ShopType.wholesale, niu: 'P1'));
      await repo.createQuote(userId: uid, lines: [SaleLine(item: a, quantity: 10, unitPrice: 600)], date: DateTime.now());
      final data = await repo.exportData(uid);

      await repo.importData(uid, data);
      final levels = await repo.priceLevels(uid);
      expect(levels.single.name, 'Gros');
      final items = await repo.inventory(uid);
      final pr = await repo.productPricing(items.single.product.id!);
      expect(pr.levelPrices[levels.single.id], 600);
      expect(pr.packs.single.quantity, 10);
      expect(items.single.product.barcode, '111');
      final client = (await repo.clientByName(uid, 'Ets Fotso'))!;
      expect(client.priceLevelId, levels.single.id);
      expect((await repo.shopProfile(uid)).niu, 'P1');
      expect((await repo.quotes(uid)).single.lines.single.quantity, 10);
    });
  });
}
