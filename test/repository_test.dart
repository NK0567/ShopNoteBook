import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopnotbook/core/stock_math.dart';
import 'package:shopnotbook/data/app_database.dart';
import 'package:shopnotbook/data/models.dart';
import 'package:shopnotbook/data/shop_repository.dart';
import 'package:shopnotbook/services/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late ShopRepository repo;
  late Session session;
  late int uid;

  setUp(() async {
    db = await AppDatabase.open(factory: testDatabaseFactory(), path: inMemoryDatabasePath);
    repo = ShopRepository(db);
    session = Session(repo, hashIterations: 1000);
    await session.register(
      name: 'Boris',
      email: 'Boris@Test.cm',
      password: 'Boutique2026',
      businessName: 'Ma boutique',
    );
    await session.login('boris@test.cm', 'Boutique2026');
    uid = session.userId;
  });

  tearDown(() => db.close());

  Future<int> addProduct({
    String ref = 'S1',
    int initial = 14,
    double cost = 500,
    double price = 900,
    int threshold = 10,
  }) => repo.saveProduct(
    uid,
    Product(
      reference: ref,
      name: 'Produit $ref',
      unit: 'unité',
      alertThreshold: threshold,
      initialStock: initial,
      initialUnitCost: cost,
      sellingPrice: price,
    ),
  );

  Future<Movement> move(MovementType t, int productId, int qty, double price, {DateTime? date}) => repo.recordMovement(
    userId: uid,
    type: t,
    productId: productId,
    quantity: qty,
    unitPrice: price,
    date: date ?? DateTime.now(),
  );

  group('Produits', () {
    test('référence normalisée et unique (insensible à la casse)', () async {
      await addProduct(ref: ' tc ');
      final items = await repo.inventory(uid);
      expect(items.single.product.reference, 'TC');
      await expectLater(addProduct(ref: 'Tc'), throwsA(isA<BusinessException>()));
    });

    test('stock d\'ouverture figé après le premier mouvement', () async {
      final id = await addProduct();
      await move(MovementType.entry, id, 5, 600);
      final p = (await repo.stockItem(uid, id))!.product;
      final changed = Product(
        id: p.id,
        reference: p.reference,
        name: p.name,
        unit: p.unit,
        alertThreshold: p.alertThreshold,
        initialStock: 99,
        initialUnitCost: p.initialUnitCost,
        sellingPrice: p.sellingPrice,
      );
      await expectLater(repo.saveProduct(uid, changed), throwsA(isA<BusinessException>()));
      await expectLater(repo.deleteProduct(uid, id), throwsA(isA<BusinessException>()));
    });
  });

  group('Inventaire et CUMP', () {
    test('reproduit le calcul du classeur "ma boutique"', () async {
      final id = await addProduct(initial: 14, cost: 500);
      await move(MovementType.entry, id, 40, 380);
      await move(MovementType.entry, id, 23, 386); // 15200 + 8878 = 24078
      final item = (await repo.stockItem(uid, id))!;
      expect(item.stock, 77);
      expect(item.cump, closeTo((7000 + 24078) / 77, 1e-9));
      expect(item.stockValue, closeTo(77 * item.cump, 1e-6));
      expect(item.status, StockStatus.ok);
    });

    test('vente : stock décrémenté, bénéfice calculé sur le CUMP du moment', () async {
      final id = await addProduct(initial: 10, cost: 500, threshold: 10);
      final sale = await move(MovementType.sale, id, 3, 900);
      expect(sale.unitCost, 500);
      expect(sale.profit, 1200);
      expect(sale.code, 'S-0001');
      final item = (await repo.stockItem(uid, id))!;
      expect(item.stock, 7);
      expect(item.status, StockStatus.needed);
      // Une entrée ultérieure à un autre prix ne modifie pas le bénéfice déjà réalisé.
      await move(MovementType.entry, id, 10, 1000);
      final s = await repo.periodSummary(uid);
      expect(s.profit, 1200);
      expect(s.salesAmount, 2700);
      expect(s.valueIn, 10000);
    });

    test('vente refusée si le stock est insuffisant (plus de stock négatif)', () async {
      final id = await addProduct(initial: 2);
      await expectLater(move(MovementType.sale, id, 3, 900), throwsA(isA<BusinessException>()));
      expect((await repo.stockItem(uid, id))!.stock, 2);
      expect(await repo.movements(uid), isEmpty);
    });

    test('date future et quantité nulle refusées', () async {
      final id = await addProduct();
      await expectLater(
        move(MovementType.entry, id, 1, 100, date: DateTime.now().add(const Duration(days: 2))),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(move(MovementType.entry, id, 0, 100), throwsA(isA<BusinessException>()));
    });
  });

  group('Annulations (historique non effaçable)', () {
    test('annuler une vente remet le stock et garde la trace', () async {
      final id = await addProduct(initial: 5);
      final sale = await move(MovementType.sale, id, 2, 900);
      await expectLater(repo.cancelMovement(uid, sale.id, ''), throwsA(isA<BusinessException>()));
      await repo.cancelMovement(uid, sale.id, 'erreur de saisie');
      expect((await repo.stockItem(uid, id))!.stock, 5);
      final all = await repo.movements(uid);
      expect(all.single.cancelled, isTrue);
      expect(all.single.cancelReason, 'erreur de saisie');
      expect((await repo.periodSummary(uid)).salesAmount, 0);
      await expectLater(repo.cancelMovement(uid, sale.id, 'encore'), throwsA(isA<BusinessException>()));
    });

    test('impossible d\'annuler une entrée déjà vendue', () async {
      final id = await addProduct(initial: 0);
      final entry = await move(MovementType.entry, id, 5, 500);
      await move(MovementType.sale, id, 4, 900);
      await expectLater(repo.cancelMovement(uid, entry.id, 'erreur'), throwsA(isA<BusinessException>()));
    });
  });

  test('analyses : classement, catégories, filtres de période', () async {
    final cat = await repo.addCategory(uid, 'Smartphone');
    await expectLater(repo.addCategory(uid, 'SMARTPHONE'), throwsA(isA<BusinessException>()));
    final a = await repo.saveProduct(
      uid,
      Product(
        reference: 'A',
        name: 'Pixel',
        categoryId: cat,
        unit: 'unité',
        alertThreshold: 1,
        initialStock: 10,
        initialUnitCost: 100,
        sellingPrice: 200,
      ),
    );
    final b = await addProduct(ref: 'B', initial: 10, cost: 50);
    await move(MovementType.sale, a, 2, 200);
    await move(MovementType.sale, b, 5, 90);
    await move(MovementType.sale, b, 1, 90, date: DateTime.now().subtract(const Duration(days: 40)));

    final ranking = await repo.salesRanking(uid);
    expect(ranking.map((r) => r.reference), ['B', 'A']);
    expect(ranking.first.quantity, 6);

    final recent = await repo.periodSummary(uid, from: DateTime.now().subtract(const Duration(days: 7)));
    expect(recent.salesCount, 2);
    final onlyPhones = await repo.periodSummary(uid, categoryId: cat);
    expect(onlyPhones.salesAmount, 400);

    final byCat = await repo.movementsByCategory(uid, MovementType.sale);
    expect({for (final c in byCat) c.category: c.value}, {'Smartphone': 400.0, 'Sans catégorie': 540.0});
  });

  test('isolation des comptes', () async {
    await addProduct();
    await session.register(name: 'Autre', email: 'autre@test.cm', password: 'Autre12345', businessName: 'B2');
    await session.login('autre@test.cm', 'Autre12345');
    expect(await repo.inventory(session.userId), isEmpty);
    final other = (await repo.inventory(uid)).single.product.id!;
    await expectLater(
      repo.recordMovement(
        userId: session.userId,
        type: MovementType.sale,
        productId: other,
        quantity: 1,
        unitPrice: 1,
        date: DateTime.now(),
      ),
      throwsA(isA<BusinessException>()),
    );
  });

  group('Session', () {
    test('mot de passe faible refusé, email déjà pris refusé', () async {
      await expectLater(
        session.register(name: 'X', email: 'x@test.cm', password: 'court', businessName: 'B'),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        session.register(name: 'X', email: 'BORIS@test.cm', password: 'Valide1234', businessName: 'B'),
        throwsA(isA<AuthException>()),
      );
    });

    test('blocage après 5 échecs, même avec le bon mot de passe', () async {
      session.logout();
      for (var i = 0; i < Session.maxAttempts; i++) {
        await expectLater(session.login('boris@test.cm', 'mauvais'), throwsA(isA<AuthException>()));
      }
      await expectLater(
        session.login('boris@test.cm', 'Boutique2026'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Trop de tentatives'))),
      );
      expect(session.isLoggedIn, isFalse);
    });

    test('verrouillage : déverrouiller exige le mot de passe', () async {
      session.lock();
      expect(session.isLocked, isTrue);
      await expectLater(session.unlock('faux'), throwsA(isA<AuthException>()));
      await session.unlock('Boutique2026');
      expect(session.isLocked, isFalse);
    });

    test('compte v1 (SHA256) migré en PBKDF2 à la connexion', () async {
      final legacy = sha256.convert('Ancien2025'.codeUnits).toString();
      await db.insert('users', {
        'name': 'Ancien',
        'email': 'ancien@test.cm',
        'passwordHash': legacy,
        'businessName': 'Vieille boutique',
        'createdAt': '2025-12-01T10:00:00',
      });
      await session.login('ancien@test.cm', 'Ancien2025');
      final row = await repo.findUserRowByEmail('ancien@test.cm');
      expect(row!['passwordHash'] as String, startsWith('pbkdf2\$'));
    });
  });

  test('migration de la base v1 vers v2', () async {
    final factory = testDatabaseFactory();
    final dir = Directory.systemTemp.createTempSync('shopbook_test');
    final path = '${dir.path}/v1.db';
    final v1 = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, _) async {
          await d.execute('''CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL, passwordHash TEXT NOT NULL, businessName TEXT NOT NULL,
        criticalStockThreshold INTEGER DEFAULT 5, warningStockThreshold INTEGER DEFAULT 10,
        warningColor TEXT DEFAULT '#FF9800', criticalColor TEXT DEFAULT '#F44336', createdAt TEXT NOT NULL)''');
          await d.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL,
        name TEXT NOT NULL, description TEXT, costPrice REAL NOT NULL, sellingPrice REAL NOT NULL,
        quantity INTEGER NOT NULL, totalSoldQuantity INTEGER DEFAULT 0, lowStockThreshold INTEGER NOT NULL,
        criticalStockThreshold INTEGER NOT NULL, category TEXT NOT NULL, unit TEXT NOT NULL,
        createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL)''');
          await d.execute('''CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL,
        productId INTEGER NOT NULL, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL,
        totalAmount REAL NOT NULL, profit REAL NOT NULL, saleDate TEXT NOT NULL, notes TEXT)''');
          await d.execute('''CREATE TABLE purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL,
        productId INTEGER NOT NULL, productName TEXT NOT NULL, quantity INTEGER NOT NULL,
        unitCostPrice REAL NOT NULL, totalCost REAL NOT NULL, supplier TEXT NOT NULL, invoiceNumber TEXT,
        purchaseDate TEXT NOT NULL, notes TEXT)''');
        },
      ),
    );
    const t = '2025-12-10T09:00:00.000';
    await v1.insert('users', {
      'name': 'A',
      'email': 'A@B.cm',
      'passwordHash': 'x',
      'businessName': 'S',
      'createdAt': t,
    });
    await v1.insert('products', {
      'userId': 1,
      'name': 'Riz',
      'costPrice': 100.0,
      'sellingPrice': 150.0,
      'quantity': 12,
      'lowStockThreshold': 5,
      'criticalStockThreshold': 2,
      'category': 'Vivres',
      'unit': 'sac',
      'createdAt': t,
      'updatedAt': t,
    });
    await v1.insert('purchases', {
      'userId': 1,
      'productId': 1,
      'productName': 'Riz',
      'quantity': 10,
      'unitCostPrice': 100.0,
      'totalCost': 1000.0,
      'supplier': 'Grossiste',
      'invoiceNumber': 'F12',
      'purchaseDate': t,
    });
    await v1.insert('sales', {
      'userId': 1,
      'productId': 1,
      'productName': 'Riz',
      'quantity': 3,
      'unitPrice': 150.0,
      'totalAmount': 450.0,
      'profit': 150.0,
      'saleDate': t,
    });
    await v1.close();
    final v2 = await AppDatabase.open(factory: factory, path: path);
    final r = ShopRepository(v2);
    final item = (await r.inventory(1)).single;
    expect(item.product.reference, 'P1');
    expect(item.categoryName, 'Vivres');
    expect(item.product.initialStock, 5); // 12 - 10 + 3
    expect(item.stock, 12);
    expect((await r.periodSummary(1)).profit, 150);
    expect((await r.movements(1, type: MovementType.entry)).single.partner, 'Grossiste');
    await v2.close();
    dir.deleteSync(recursive: true);
  });
}
