import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shopnotbook/data/app_database.dart';
import 'package:shopnotbook/data/models.dart';
import 'package:shopnotbook/data/shop_repository.dart';
import 'package:shopnotbook/services/backup_service.dart';
import 'package:shopnotbook/services/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// Panier, crédits, pertes, inventaire, code de secours, sauvegarde (schéma v3).
void main() {
  late Database db;
  late ShopRepository repo;
  late Session session;
  late int uid;
  late String recoveryCode;

  setUp(() async {
    db = await AppDatabase.open(factory: testDatabaseFactory(), path: inMemoryDatabasePath);
    repo = ShopRepository(db);
    session = Session(repo, hashIterations: 1000);
    recoveryCode = await session.register(
      name: 'Awa',
      email: 'awa@test.cm',
      password: 'Boutique2026',
      businessName: 'Chez Awa',
    );
    await session.login('awa@test.cm', 'Boutique2026');
    uid = session.userId;
  });

  tearDown(() => db.close());

  Future<StockItem> product(String ref, {int stock = 10, double cost = 500, double price = 800}) async {
    final id = await repo.saveProduct(
      uid,
      Product(
        reference: ref,
        name: 'Produit $ref',
        unit: 'unité',
        alertThreshold: 2,
        initialStock: stock,
        initialUnitCost: cost,
        sellingPrice: price,
      ),
    );
    return (await repo.stockItem(uid, id))!;
  }

  SaleLine line(StockItem i, int q, [double? price]) =>
      SaleLine(item: i, quantity: q, unitPrice: price ?? i.product.sellingPrice);

  group('Panier', () {
    test('vente de plusieurs articles en un ticket, payée comptant', () async {
      final a = await product('A');
      final b = await product('B', cost: 100, price: 250);
      final d = await repo.recordSale(
        userId: uid,
        lines: [line(a, 2), line(b, 4)],
        date: DateTime.now(),
        paid: 5000,
      );
      expect(d.ticket.code, 'T-0001');
      expect(d.lines.length, 2);
      expect(d.ticket.total, 2600);
      expect(d.ticket.paid, 2600); // le surplus (monnaie rendue) n'est pas encaissé
      expect(d.ticket.balance, 0);
      expect((await repo.stockItem(uid, a.product.id!))!.stock, 8);
      expect((await repo.stockItem(uid, b.product.id!))!.stock, 6);
      final s = await repo.periodSummary(uid);
      expect(s.salesCount, 1); // un ticket = une vente
      expect(s.salesAmount, 2600);
      expect(s.profit, 2 * 300 + 4 * 150);
      expect(s.cashIn, 2600);
    });

    test('le même produit sur deux lignes ne peut pas dépasser le stock', () async {
      final a = await product('A', stock: 3);
      await expectLater(
        repo.recordSale(userId: uid, lines: [line(a, 2), line(a, 2)], date: DateTime.now(), paid: 3200),
        throwsA(isA<BusinessException>()),
      );
      expect((await repo.stockItem(uid, a.product.id!))!.stock, 3);
      expect(await repo.tickets(uid), isEmpty);
    });

    test('panier vide refusé', () async {
      await expectLater(
        repo.recordSale(userId: uid, lines: const [], date: DateTime.now(), paid: 0),
        throwsA(isA<BusinessException>()),
      );
    });
  });

  group('Crédits clients', () {
    test('vente à crédit : nom du client obligatoire', () async {
      final a = await product('A');
      await expectLater(
        repo.recordSale(userId: uid, lines: [line(a, 1)], date: DateTime.now(), paid: 0),
        throwsA(isA<BusinessException>()),
      );
    });

    test('acompte, puis remboursement réparti du plus ancien au plus récent', () async {
      final a = await product('A');
      final t1 = await repo.recordSale(
        userId: uid,
        lines: [line(a, 2)],
        date: DateTime.now().subtract(const Duration(days: 3)),
        client: 'Mme Ngo',
        paid: 600,
      );
      final t2 = await repo.recordSale(
        userId: uid,
        lines: [line(a, 1)],
        date: DateTime.now(),
        client: 'mme ngo',
        paid: 0,
      );
      expect(t1.ticket.balance, 1000);
      final debts = await repo.clientDebts(uid);
      expect(debts.single.balance, 1800);
      expect(debts.single.ticketCount, 2);
      expect(await repo.totalCredit(uid), 1800);

      await expectLater(repo.payClientDebt(uid, 'Mme Ngo', 5000), throwsA(isA<BusinessException>()));
      await repo.payClientDebt(uid, 'Mme Ngo', 1200, method: 'Mobile Money');
      expect((await repo.ticketDetail(uid, t1.ticket.id))!.ticket.balance, 0);
      expect((await repo.ticketDetail(uid, t2.ticket.id))!.ticket.balance, 600);

      await repo.addPayment(uid, t2.ticket.id, 600);
      expect(await repo.clientDebts(uid), isEmpty);
      expect((await repo.periodSummary(uid)).cashIn, 2400);
    });

    test('annuler un encaissement remet la dette', () async {
      final a = await product('A');
      final t = await repo.recordSale(userId: uid, lines: [line(a, 1)], date: DateTime.now(), client: 'Paul', paid: 0);
      await repo.addPayment(uid, t.ticket.id, 800);
      final p = (await repo.ticketDetail(uid, t.ticket.id))!.payments.single;
      await repo.cancelPayment(uid, p.id);
      expect((await repo.ticketDetail(uid, t.ticket.id))!.ticket.balance, 800);
    });

    test('annuler une ligne payée : la somme à rendre est notée sur le ticket', () async {
      final a = await product('A');
      final b = await product('B', price: 1000);
      final t = await repo.recordSale(userId: uid, lines: [line(a, 1), line(b, 1)], date: DateTime.now(), paid: 1800);
      final lineB = t.lines.firstWhere((m) => m.productReference == 'B');
      final refund = await repo.cancelMovement(uid, lineB.id, 'client a changé d\'avis');
      expect(refund, 1000);
      final after = (await repo.ticketDetail(uid, t.ticket.id))!;
      expect(after.ticket.total, 800);
      expect(after.ticket.paid, 800);
      expect(after.payments.where((p) => p.isRefund).single.amount, -1000);
      expect((await repo.stockItem(uid, b.product.id!))!.stock, 10);
    });
  });

  group('Pertes et inventaire', () {
    test('perte : sort du stock, valorisée au CUMP, déduite du bénéfice net', () async {
      final a = await product('A', cost: 500);
      await expectLater(
        repo.recordMovement(userId: uid, type: MovementType.loss, productId: a.product.id!, quantity: 1, unitPrice: 0, date: DateTime.now()),
        throwsA(isA<BusinessException>()), // motif obligatoire
      );
      final m = await repo.recordMovement(
        userId: uid,
        type: MovementType.loss,
        productId: a.product.id!,
        quantity: 3,
        unitPrice: 0,
        date: DateTime.now(),
        note: 'Casse',
      );
      expect(m.code, 'P-0001');
      expect(m.lossValue, 1500);
      final item = (await repo.stockItem(uid, a.product.id!))!;
      expect(item.stock, 7);
      expect(item.cump, 500);
      await repo.recordSale(userId: uid, lines: [line(item, 2)], date: DateTime.now(), paid: 1600);
      final s = await repo.periodSummary(uid);
      expect(s.valueLoss, 1500);
      expect(s.netProfit, 600 - 1500);
    });

    test('perte supérieure au stock refusée', () async {
      final a = await product('A', stock: 2);
      await expectLater(
        repo.recordMovement(userId: uid, type: MovementType.loss, productId: a.product.id!, quantity: 3, unitPrice: 0, date: DateTime.now(), note: 'Vol'),
        throwsA(isA<BusinessException>()),
      );
    });

    test('inventaire : manquant en perte, surplus en entrée au CUMP, stock juste sans écriture', () async {
      final a = await product('A', stock: 10, cost: 400);
      final loss = await repo.adjustStockToCount(userId: uid, productId: a.product.id!, counted: 7, reason: 'casse');
      expect(loss!.type, MovementType.loss);
      expect(loss.quantity, 3);
      final gain = await repo.adjustStockToCount(userId: uid, productId: a.product.id!, counted: 9, reason: '');
      expect(gain!.type, MovementType.entry);
      expect(gain.unitPrice, 400);
      final item = (await repo.stockItem(uid, a.product.id!))!;
      expect(item.stock, 9);
      expect(item.cump, 400);
      expect(await repo.adjustStockToCount(userId: uid, productId: a.product.id!, counted: 9, reason: ''), isNull);
    });
  });

  group('Code de secours', () {
    test('réinitialise le mot de passe et change de code', () async {
      expect(recoveryCode, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$')));
      session.logout();
      await expectLater(
        session.resetPasswordWithCode(email: 'awa@test.cm', code: 'AAAA-BBBB-CCCC', newPassword: 'Nouveau2026'),
        throwsA(isA<AuthException>()),
      );
      final next = await session.resetPasswordWithCode(
        email: 'awa@test.cm',
        code: recoveryCode.toLowerCase().replaceAll('-', ' '),
        newPassword: 'Nouveau2026',
      );
      expect(next, isNot(recoveryCode));
      await expectLater(session.login('awa@test.cm', 'Boutique2026'), throwsA(isA<AuthException>()));
      await session.login('awa@test.cm', 'Nouveau2026');
      expect(session.user!.hasRecoveryCode, isTrue);
      // L'ancien code ne fonctionne plus.
      session.logout();
      await expectLater(
        session.resetPasswordWithCode(email: 'awa@test.cm', code: recoveryCode, newPassword: 'Encore2026x'),
        throwsA(isA<AuthException>()),
      );
    });

    test('régénération : exige le mot de passe', () async {
      await expectLater(session.regenerateRecoveryCode('faux'), throwsA(isA<AuthException>()));
      final code = await session.regenerateRecoveryCode('Boutique2026');
      expect(code, isNot(recoveryCode));
    });
  });

  test('sauvegarde chiffrée : aller-retour complet vers un autre compte', () async {
    final cat = await repo.addCategory(uid, 'Boissons');
    final id = await repo.saveProduct(
      uid,
      Product(
        reference: 'COCA',
        name: 'Coca 33 cl',
        categoryId: cat,
        unit: 'canette',
        alertThreshold: 12,
        initialStock: 24,
        initialUnitCost: 300,
        sellingPrice: 500,
      ),
    );
    final item = (await repo.stockItem(uid, id))!;
    await repo.recordSale(userId: uid, lines: [line(item, 5)], date: DateTime.now(), client: 'Jean', paid: 1000);
    await repo.recordMovement(userId: uid, type: MovementType.loss, productId: id, quantity: 1, unitPrice: 0, date: DateTime.now(), note: 'Périmé');

    final bytes = await BackupService.encrypt(await repo.exportData(uid), 'motdepasse', iter: 1000);
    await expectLater(BackupService.decrypt(bytes, 'mauvais'), throwsA(isA<BusinessException>()));
    final data = await BackupService.decrypt(bytes, 'motdepasse');

    await session.register(name: 'Awa 2', email: 'awa2@test.cm', password: 'Boutique2026', businessName: 'Nouveau tel');
    await session.login('awa2@test.cm', 'Boutique2026');
    final uid2 = session.userId;
    await repo.importData(uid2, data);

    final restored = (await repo.inventory(uid2)).single;
    expect(restored.product.reference, 'COCA');
    expect(restored.categoryName, 'Boissons');
    expect(restored.stock, 18);
    expect((await repo.clientDebts(uid2)).single.balance, 1500);
    expect((await repo.periodSummary(uid2)).valueLoss, 300);
    // Le compte d'origine n'est pas touché.
    expect((await repo.inventory(uid)).single.stock, 18);
    await expectLater(repo.importData(uid2, {'format': 'autre'}), throwsA(isA<BusinessException>()));
  });

  test('export CSV lisible par Excel', () async {
    final a = await product('A;B');
    await repo.recordSale(userId: uid, lines: [line(a, 1)], date: DateTime.now(), paid: 800);
    final inv = await repo.inventoryCsv(uid);
    expect(inv.split('\n').first, startsWith('Référence;Désignation'));
    expect(inv, contains('"A;B"'));
    final mv = await repo.movementsCsv(uid);
    expect(mv, contains('T-1'));
  });

  test('migration v2 → v3 : les ventes existantes restent payées', () async {
    final dir = Directory.systemTemp.createTempSync('shopbook_v2');
    final path = '${dir.path}/v2.db';
    final factory = testDatabaseFactory();
    final v2 = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, _) async {
          await d.execute(
            'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, '
            'passwordHash TEXT NOT NULL, businessName TEXT NOT NULL, defaultAlertThreshold INTEGER NOT NULL DEFAULT 10, '
            'warningColor INTEGER NOT NULL DEFAULT 4294940672, criticalColor INTEGER NOT NULL DEFAULT 4294198070, '
            'autoLockMinutes INTEGER NOT NULL DEFAULT 5, failedAttempts INTEGER NOT NULL DEFAULT 0, lockedUntil TEXT, createdAt TEXT NOT NULL)',
          );
          await d.execute(
            'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, name TEXT NOT NULL)',
          );
          await d.execute(
            'CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, reference TEXT NOT NULL, '
            'name TEXT NOT NULL, categoryId INTEGER, unit TEXT NOT NULL, alertThreshold INTEGER NOT NULL, '
            'initialStock INTEGER NOT NULL, initialUnitCost REAL NOT NULL, sellingPrice REAL NOT NULL, '
            'archived INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL)',
          );
          await d.execute(
            "CREATE TABLE movements (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, productId INTEGER NOT NULL, "
            "type TEXT NOT NULL CHECK (type IN ('IN', 'OUT')), number INTEGER NOT NULL, date TEXT NOT NULL, "
            'quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, unitCost REAL NOT NULL, partner TEXT, note TEXT, '
            'cancelled INTEGER NOT NULL DEFAULT 0, cancelReason TEXT, cancelledAt TEXT, createdAt TEXT NOT NULL)',
          );
          await d.execute(
            'CREATE TABLE audit_log (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, action TEXT NOT NULL, '
            'details TEXT NOT NULL, createdAt TEXT NOT NULL)',
          );
        },
      ),
    );
    const t = '2026-09-10T10:00:00';
    await v2.insert('users', {'name': 'A', 'email': 'a@b.cm', 'passwordHash': 'x', 'businessName': 'S', 'createdAt': t});
    await v2.insert('products', {
      'userId': 1,
      'reference': 'R',
      'name': 'Riz',
      'unit': 'sac',
      'alertThreshold': 2,
      'initialStock': 10,
      'initialUnitCost': 100.0,
      'sellingPrice': 150.0,
      'createdAt': t,
      'updatedAt': t,
    });
    await v2.insert('movements', {
      'userId': 1,
      'productId': 1,
      'type': 'OUT',
      'number': 1,
      'date': t,
      'quantity': 4,
      'unitPrice': 150.0,
      'unitCost': 100.0,
      'createdAt': t,
    });
    await v2.close();

    final v3 = await AppDatabase.open(factory: factory, path: path);
    final r = ShopRepository(v3);
    expect((await r.inventory(1)).single.stock, 6);
    expect(await r.clientDebts(1), isEmpty);
    final s = await r.periodSummary(1);
    expect(s.cashIn, 600);
    expect(s.profit, 200);
    // Le nouveau schéma accepte les pertes et les tickets.
    final item = (await r.inventory(1)).single;
    await r.recordMovement(userId: 1, type: MovementType.loss, productId: item.product.id!, quantity: 1, unitPrice: 0, date: DateTime.now(), note: 'Casse');
    await r.recordSale(userId: 1, lines: [SaleLine(item: item, quantity: 1, unitPrice: 150)], date: DateTime.now(), paid: 150);
    expect((await r.inventory(1)).single.stock, 4);
    await v3.close();
    dir.deleteSync(recursive: true);
  });
}
