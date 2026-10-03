import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'models.dart';

/// Erreur métier affichable telle quelle à l'utilisateur.
class BusinessException implements Exception {
  final String message;
  const BusinessException(this.message);
  @override
  String toString() => message;
}

/// Accès aux données. Toutes les requêtes sont filtrées par `userId` :
/// un commerçant ne voit jamais les données d'un autre compte.
/// Les opérations qui modifient le stock sont exécutées dans une transaction.
class ShopRepository extends ChangeNotifier {
  ShopRepository(this.db);

  final Database db;

  /// Incrémenté à chaque modification : les écrans s'en servent pour se rafraîchir.
  int revision = 0;

  void _changed() {
    revision++;
    notifyListeners();
  }

  static final _isoFmt = DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  /// Dates stockées en heure locale, à la seconde, triables comme du texte.
  static String iso(DateTime d) => _isoFmt.format(d);

  static String _now() => iso(DateTime.now());

  // ======================================================================
  // Utilisateurs (utilisé par Session)
  // ======================================================================

  Future<Map<String, Object?>?> findUserRowByEmail(String email) async {
    final rows = await db.query('users', where: 'email = ?', whereArgs: [email.trim().toLowerCase()]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findUserRowById(int id) async {
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> createUser({
    required String name,
    required String email,
    required String passwordHash,
    required String businessName,
  }) async {
    final id = await db.insert('users', {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'passwordHash': passwordHash,
      'businessName': businessName.trim(),
      'createdAt': _now(),
    });
    await audit(id, 'Compte', 'Création du compte');
    return id;
  }

  Future<void> updateLoginState(int userId, {required int failedAttempts, DateTime? lockedUntil}) => db.update(
    'users',
    {'failedAttempts': failedAttempts, 'lockedUntil': lockedUntil == null ? null : iso(lockedUntil)},
    where: 'id = ?',
    whereArgs: [userId],
  );

  Future<void> setPasswordHash(int userId, String hash) =>
      db.update('users', {'passwordHash': hash}, where: 'id = ?', whereArgs: [userId]);

  Future<void> updateUserSettings(AppUser u) async {
    await db.update(
      'users',
      {
        'name': u.name,
        'businessName': u.businessName,
        'defaultAlertThreshold': u.defaultAlertThreshold,
        'warningColor': u.warningColor,
        'criticalColor': u.criticalColor,
        'autoLockMinutes': u.autoLockMinutes,
      },
      where: 'id = ?',
      whereArgs: [u.id],
    );
    await audit(u.id, 'Réglages', 'Paramètres mis à jour');
    _changed();
  }

  // ======================================================================
  // Journal d'audit
  // ======================================================================

  Future<void> audit(int userId, String action, String details, {DatabaseExecutor? executor}) => (executor ?? db)
      .insert('audit_log', {'userId': userId, 'action': action, 'details': details, 'createdAt': _now()});

  Future<List<AuditEntry>> auditLog(int userId, {int limit = 200}) async {
    final rows = await db.query(
      'audit_log',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows
        .map((r) => AuditEntry(DateTime.parse(r['createdAt'] as String), r['action'] as String, r['details'] as String))
        .toList();
  }

  // ======================================================================
  // Catégories (liste fermée : fini "Smart phone" / "SmartPhone" / "SMARTPHONE")
  // ======================================================================

  Future<List<Category>> categories(int userId) async {
    final rows = await db.query('categories', where: 'userId = ?', whereArgs: [userId], orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> addCategory(int userId, String rawName) async {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const BusinessException('Le nom de la catégorie est obligatoire');
    final existing = await db.query('categories', where: 'userId = ? AND name = ?', whereArgs: [userId, name]);
    if (existing.isNotEmpty) throw BusinessException('La catégorie "$name" existe déjà');
    final id = await db.insert('categories', {'userId': userId, 'name': name});
    await audit(userId, 'Catégorie', 'Ajout de "$name"');
    _changed();
    return id;
  }

  Future<void> renameCategory(int userId, int categoryId, String rawName) async {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const BusinessException('Le nom de la catégorie est obligatoire');
    final clash = await db.query(
      'categories',
      where: 'userId = ? AND name = ? AND id <> ?',
      whereArgs: [userId, name, categoryId],
    );
    if (clash.isNotEmpty) throw BusinessException('La catégorie "$name" existe déjà');
    await db.update('categories', {'name': name}, where: 'id = ? AND userId = ?', whereArgs: [categoryId, userId]);
    await audit(userId, 'Catégorie', 'Renommée en "$name"');
    _changed();
  }

  Future<void> deleteCategory(int userId, int categoryId) async {
    await db.transaction((txn) async {
      await txn.update(
        'products',
        {'categoryId': null},
        where: 'categoryId = ? AND userId = ?',
        whereArgs: [categoryId, userId],
      );
      await txn.delete('categories', where: 'id = ? AND userId = ?', whereArgs: [categoryId, userId]);
      await audit(userId, 'Catégorie', 'Suppression de la catégorie #$categoryId', executor: txn);
    });
    _changed();
  }

  // ======================================================================
  // Produits (feuille "Marchandise")
  // ======================================================================

  Future<bool> hasMovements(int productId) async {
    final r = await db.rawQuery('SELECT 1 FROM movements WHERE productId = ? LIMIT 1', [productId]);
    return r.isNotEmpty;
  }

  /// Crée ou met à jour un produit. Retourne son id.
  Future<int> saveProduct(int userId, Product p) async {
    final reference = Product.normalizeReference(p.reference);
    final name = p.name.trim();
    if (reference.isEmpty) throw const BusinessException('La référence est obligatoire');
    if (name.isEmpty) throw const BusinessException('La désignation est obligatoire');
    if (p.alertThreshold < 0 || p.initialStock < 0 || p.initialUnitCost < 0 || p.sellingPrice < 0) {
      throw const BusinessException('Les quantités et prix ne peuvent pas être négatifs');
    }

    final id = await db.transaction<int>((txn) async {
      final clash = await txn.query(
        'products',
        where: 'userId = ? AND reference = ? AND id <> ?',
        whereArgs: [userId, reference, p.id ?? -1],
      );
      if (clash.isNotEmpty) {
        throw BusinessException('La référence "$reference" est déjà utilisée par "${clash.first['name']}"');
      }
      if (p.categoryId != null) {
        final cat = await txn.query('categories', where: 'id = ? AND userId = ?', whereArgs: [p.categoryId, userId]);
        if (cat.isEmpty) throw const BusinessException('Catégorie inconnue');
      }

      final values = <String, Object?>{
        'reference': reference,
        'name': name,
        'categoryId': p.categoryId,
        'unit': p.unit.trim().isEmpty ? 'unité' : p.unit.trim(),
        'alertThreshold': p.alertThreshold,
        'sellingPrice': p.sellingPrice,
        'updatedAt': _now(),
      };

      if (p.id == null) {
        values.addAll({
          'userId': userId,
          'initialStock': p.initialStock,
          'initialUnitCost': p.initialUnitCost,
          'createdAt': _now(),
        });
        final newId = await txn.insert('products', values);
        await audit(userId, 'Produit', 'Création $reference — $name (stock initial ${p.initialStock})', executor: txn);
        return newId;
      }

      final current = await txn.query('products', where: 'id = ? AND userId = ?', whereArgs: [p.id, userId]);
      if (current.isEmpty) throw const BusinessException('Produit introuvable');
      final old = Product.fromMap(current.first);
      final used = (await txn.rawQuery('SELECT 1 FROM movements WHERE productId = ? LIMIT 1', [p.id])).isNotEmpty;
      final openingChanged = old.initialStock != p.initialStock || old.initialUnitCost != p.initialUnitCost;
      if (openingChanged && used) {
        // Le stock d'ouverture fait partie de l'historique : il est figé dès le premier mouvement.
        throw const BusinessException(
          'Stock initial et coût initial ne sont plus modifiables après une entrée ou une sortie. '
          'Utilisez une entrée de stock.',
        );
      }
      values['initialStock'] = p.initialStock;
      values['initialUnitCost'] = p.initialUnitCost;
      await txn.update('products', values, where: 'id = ? AND userId = ?', whereArgs: [p.id, userId]);

      final changes = <String>[];
      if (old.name != name) changes.add('désignation');
      if (old.reference != reference) changes.add('référence ${old.reference}→$reference');
      if (old.sellingPrice != p.sellingPrice) {
        changes.add('prix de vente ${old.sellingPrice.round()}→${p.sellingPrice.round()}');
      }
      if (old.alertThreshold != p.alertThreshold) changes.add('seuil ${old.alertThreshold}→${p.alertThreshold}');
      if (openingChanged) changes.add('stock d\'ouverture');
      await audit(
        userId,
        'Produit',
        'Modification $reference${changes.isEmpty ? '' : ' : ${changes.join(', ')}'}',
        executor: txn,
      );
      return p.id!;
    });
    _changed();
    return id;
  }

  Future<void> setArchived(int userId, int productId, bool archived) async {
    await db.update(
      'products',
      {'archived': archived ? 1 : 0, 'updatedAt': _now()},
      where: 'id = ? AND userId = ?',
      whereArgs: [productId, userId],
    );
    await audit(userId, 'Produit', '${archived ? 'Archivage' : 'Réactivation'} du produit #$productId');
    _changed();
  }

  /// Suppression définitive : seulement si le produit n'a jamais bougé.
  Future<void> deleteProduct(int userId, int productId) async {
    await db.transaction((txn) async {
      final used = (await txn.rawQuery('SELECT 1 FROM movements WHERE productId = ? LIMIT 1', [productId])).isNotEmpty;
      if (used) {
        throw const BusinessException('Ce produit a un historique : archivez-le au lieu de le supprimer.');
      }
      await txn.delete('products', where: 'id = ? AND userId = ?', whereArgs: [productId, userId]);
      await audit(userId, 'Produit', 'Suppression du produit #$productId', executor: txn);
    });
    _changed();
  }

  // ======================================================================
  // Inventaire (feuille "Inventaire", calculée en temps réel)
  // ======================================================================

  static const _inventorySql = '''
    SELECT p.*, c.name AS categoryName,
      COALESCE(SUM(CASE WHEN m.type = 'IN'  THEN m.quantity END), 0) AS qtyIn,
      COALESCE(SUM(CASE WHEN m.type = 'IN'  THEN m.quantity * m.unitPrice END), 0) AS valueIn,
      COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity END), 0) AS qtyOut,
      COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity * m.unitPrice END), 0) AS salesAmount,
      COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity * (m.unitPrice - m.unitCost) END), 0) AS profit
    FROM products p
    LEFT JOIN categories c ON c.id = p.categoryId
    LEFT JOIN movements m ON m.productId = p.id AND m.cancelled = 0
  ''';

  static StockItem _stockItemFromRow(Map<String, Object?> r) => StockItem(
    product: Product.fromMap(r),
    categoryName: r['categoryName'] as String?,
    qtyIn: (r['qtyIn'] as num).toInt(),
    valueIn: (r['valueIn'] as num).toDouble(),
    qtyOut: (r['qtyOut'] as num).toInt(),
    salesAmount: (r['salesAmount'] as num).toDouble(),
    profit: (r['profit'] as num).toDouble(),
  );

  Future<List<StockItem>> inventory(int userId, {bool includeArchived = false}) async {
    final rows = await db.rawQuery(
      '$_inventorySql WHERE p.userId = ? ${includeArchived ? '' : 'AND p.archived = 0'} '
      'GROUP BY p.id ORDER BY p.name COLLATE NOCASE',
      [userId],
    );
    return rows.map(_stockItemFromRow).toList();
  }

  Future<StockItem?> stockItem(int userId, int productId, {DatabaseExecutor? executor}) async {
    final rows = await (executor ?? db).rawQuery('$_inventorySql WHERE p.userId = ? AND p.id = ? GROUP BY p.id', [
      userId,
      productId,
    ]);
    return rows.isEmpty ? null : _stockItemFromRow(rows.first);
  }

  // ======================================================================
  // Mouvements (feuilles "Opération", "Entrée", "Sortie")
  // ======================================================================

  /// Enregistre une entrée (achat fournisseur) ou une sortie (vente).
  /// Une sortie est refusée si le stock disponible est insuffisant.
  Future<Movement> recordMovement({
    required int userId,
    required MovementType type,
    required int productId,
    required int quantity,
    required double unitPrice,
    required DateTime date,
    String? partner,
    String? note,
  }) async {
    if (quantity <= 0) throw const BusinessException('La quantité doit être supérieure à 0');
    if (unitPrice < 0) throw const BusinessException('Le prix ne peut pas être négatif');
    if (type == MovementType.entry && unitPrice == 0) {
      throw const BusinessException('Le coût d\'achat doit être supérieur à 0');
    }
    if (date.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw const BusinessException('La date ne peut pas être dans le futur');
    }

    final id = await db.transaction<int>((txn) async {
      final item = await stockItem(userId, productId, executor: txn);
      if (item == null) throw const BusinessException('Produit introuvable');
      if (item.product.archived) throw const BusinessException('Ce produit est archivé');
      if (type == MovementType.sale && quantity > item.stock) {
        throw BusinessException(
          'Stock insuffisant pour ${item.product.name} : ${Fmt.qtyUnit(item.stock < 0 ? 0 : item.stock, item.product.unit)} en stock',
        );
      }

      final next = await txn.rawQuery(
        'SELECT COALESCE(MAX(number), 0) + 1 AS n FROM movements WHERE userId = ? AND type = ?',
        [userId, type.code],
      );
      final number = (next.first['n'] as num).toInt();
      // Pour une vente, on fige le CUMP du moment : le bénéfice ne change plus ensuite.
      final unitCost = type == MovementType.sale ? item.cump : unitPrice;

      final newId = await txn.insert('movements', {
        'userId': userId,
        'productId': productId,
        'type': type.code,
        'number': number,
        'date': iso(date),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'unitCost': unitCost,
        'partner': _clean(partner),
        'note': _clean(note),
        'createdAt': _now(),
      });
      await audit(
        userId,
        type.label,
        '${type == MovementType.entry ? 'E' : 'S'}-$number ${item.product.reference} '
        'x$quantity à ${unitPrice.round()} FCFA',
        executor: txn,
      );
      return newId;
    });
    _changed();
    return (await movements(userId, movementId: id)).first;
  }

  /// Annule un mouvement (il reste visible, barré, dans l'historique).
  Future<void> cancelMovement(int userId, int movementId, String reason) async {
    final why = reason.trim();
    if (why.length < 3) throw const BusinessException('Indiquez le motif de l\'annulation');
    await db.transaction((txn) async {
      final rows = await txn.query('movements', where: 'id = ? AND userId = ?', whereArgs: [movementId, userId]);
      if (rows.isEmpty) throw const BusinessException('Opération introuvable');
      final m = rows.first;
      if ((m['cancelled'] as int) == 1) throw const BusinessException('Opération déjà annulée');
      if (m['type'] == 'IN') {
        final item = await stockItem(userId, m['productId'] as int, executor: txn);
        final qty = m['quantity'] as int;
        if (item != null && item.stock - qty < 0) {
          throw BusinessException(
            'Annulation impossible : une partie de cette entrée a déjà été vendue (stock actuel ${item.stock}).',
          );
        }
      }
      await txn.update(
        'movements',
        {'cancelled': 1, 'cancelReason': why, 'cancelledAt': _now()},
        where: 'id = ?',
        whereArgs: [movementId],
      );
      await audit(
        userId,
        'Annulation',
        '${m['type'] == 'IN' ? 'E' : 'S'}-${m['number']} annulée : $why',
        executor: txn,
      );
    });
    _changed();
  }

  Future<List<Movement>> movements(
    int userId, {
    int? movementId,
    MovementType? type,
    DateTime? from,
    DateTime? to,
    int? productId,
    int? categoryId,
    bool includeCancelled = true,
    String? search,
    int? limit,
  }) async {
    final where = <String>['m.userId = ?'];
    final args = <Object?>[userId];
    if (movementId != null) {
      where.add('m.id = ?');
      args.add(movementId);
    }
    if (type != null) {
      where.add('m.type = ?');
      args.add(type.code);
    }
    if (from != null) {
      where.add('m.date >= ?');
      args.add(iso(from));
    }
    if (to != null) {
      where.add('m.date < ?');
      args.add(iso(to));
    }
    if (productId != null) {
      where.add('m.productId = ?');
      args.add(productId);
    }
    if (categoryId != null) {
      where.add('p.categoryId = ?');
      args.add(categoryId);
    }
    if (!includeCancelled) where.add('m.cancelled = 0');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(p.name LIKE ? OR p.reference LIKE ? OR m.partner LIKE ?)');
      final like = '%${search.trim()}%';
      args.addAll([like, like, like]);
    }
    final rows = await db.rawQuery('''
      SELECT m.*, p.reference, p.name AS productName, p.unit, c.name AS categoryName
      FROM movements m
      JOIN products p ON p.id = m.productId
      LEFT JOIN categories c ON c.id = p.categoryId
      WHERE ${where.join(' AND ')}
      ORDER BY m.date DESC, m.id DESC
      ${limit != null ? 'LIMIT $limit' : ''}
    ''', args);
    return rows.map(Movement.fromMap).toList();
  }

  /// Fournisseurs / clients déjà saisis (auto-complétion).
  Future<List<String>> partners(int userId, MovementType type) async {
    final rows = await db.rawQuery(
      '''
      SELECT partner, COUNT(*) AS n FROM movements
      WHERE userId = ? AND type = ? AND partner IS NOT NULL AND partner <> ''
      GROUP BY partner COLLATE NOCASE ORDER BY n DESC LIMIT 50
    ''',
      [userId, type.code],
    );
    return rows.map((r) => r['partner'] as String).toList();
  }

  // ======================================================================
  // Analyses (feuilles "Traitement" / "Tableau de bord")
  // ======================================================================

  String _periodFilter(List<Object?> args, DateTime? from, DateTime? to, int? categoryId) {
    final sb = StringBuffer();
    if (from != null) {
      sb.write(' AND m.date >= ?');
      args.add(iso(from));
    }
    if (to != null) {
      sb.write(' AND m.date < ?');
      args.add(iso(to));
    }
    if (categoryId != null) {
      sb.write(' AND p.categoryId = ?');
      args.add(categoryId);
    }
    return sb.toString();
  }

  Future<PeriodSummary> periodSummary(int userId, {DateTime? from, DateTime? to, int? categoryId}) async {
    final args = <Object?>[userId];
    final filter = _periodFilter(args, from, to, categoryId);
    final r = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN m.type = 'IN'  THEN m.quantity END), 0) AS qtyIn,
        COALESCE(SUM(CASE WHEN m.type = 'IN'  THEN m.quantity * m.unitPrice END), 0) AS valueIn,
        COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity END), 0) AS qtyOut,
        COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity * m.unitPrice END), 0) AS salesAmount,
        COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity * (m.unitPrice - m.unitCost) END), 0) AS profit,
        COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN 1 END), 0) AS salesCount
      FROM movements m JOIN products p ON p.id = m.productId
      WHERE m.userId = ? AND m.cancelled = 0 $filter
    ''', args)).first;
    return PeriodSummary(
      qtyIn: (r['qtyIn'] as num).toInt(),
      valueIn: (r['valueIn'] as num).toDouble(),
      qtyOut: (r['qtyOut'] as num).toInt(),
      salesAmount: (r['salesAmount'] as num).toDouble(),
      profit: (r['profit'] as num).toDouble(),
      salesCount: (r['salesCount'] as num).toInt(),
    );
  }

  /// Classement des produits les plus vendus (par chiffre d'affaires).
  Future<List<ProductRanking>> salesRanking(
    int userId, {
    DateTime? from,
    DateTime? to,
    int? categoryId,
    int limit = 15,
  }) async {
    final args = <Object?>[userId];
    final filter = _periodFilter(args, from, to, categoryId);
    final rows = await db.rawQuery('''
      SELECT p.id, p.reference, p.name,
        SUM(m.quantity) AS qty,
        SUM(m.quantity * m.unitPrice) AS amount,
        SUM(m.quantity * (m.unitPrice - m.unitCost)) AS profit
      FROM movements m JOIN products p ON p.id = m.productId
      WHERE m.userId = ? AND m.type = 'OUT' AND m.cancelled = 0 $filter
      GROUP BY p.id ORDER BY amount DESC, qty DESC LIMIT $limit
    ''', args);
    return rows
        .map(
          (r) => ProductRanking(
            productId: r['id'] as int,
            reference: r['reference'] as String,
            name: r['name'] as String,
            quantity: (r['qty'] as num).toInt(),
            amount: (r['amount'] as num).toDouble(),
            profit: (r['profit'] as num).toDouble(),
          ),
        )
        .toList();
  }

  /// Ventes (ou entrées) par catégorie sur une période.
  Future<List<CategoryShare>> movementsByCategory(int userId, MovementType type, {DateTime? from, DateTime? to}) async {
    final args = <Object?>[userId, type.code];
    final filter = _periodFilter(args, from, to, null);
    final rows = await db.rawQuery('''
      SELECT COALESCE(c.name, 'Sans catégorie') AS cat, SUM(m.quantity * m.unitPrice) AS total
      FROM movements m JOIN products p ON p.id = m.productId
      LEFT JOIN categories c ON c.id = p.categoryId
      WHERE m.userId = ? AND m.type = ? AND m.cancelled = 0 $filter
      GROUP BY cat ORDER BY total DESC
    ''', args);
    return rows.map((r) => CategoryShare(r['cat'] as String, (r['total'] as num).toDouble())).toList();
  }

  /// Ventes et bénéfice par jour (courbe du tableau de bord).
  Future<Map<DateTime, double>> dailySales(int userId, {required DateTime from, required DateTime to}) async {
    final rows = await db.rawQuery(
      '''
      SELECT substr(m.date, 1, 10) AS day, SUM(m.quantity * m.unitPrice) AS total
      FROM movements m
      WHERE m.userId = ? AND m.type = 'OUT' AND m.cancelled = 0 AND m.date >= ? AND m.date < ?
      GROUP BY day
    ''',
      [userId, iso(from), iso(to)],
    );
    return {for (final r in rows) DateTime.parse(r['day'] as String): (r['total'] as num).toDouble()};
  }

  static List<CategoryShare> stockValueByCategory(List<StockItem> items) {
    final map = <String, double>{};
    for (final i in items) {
      final key = i.categoryName ?? 'Sans catégorie';
      map[key] = (map[key] ?? 0) + i.stockValue;
    }
    final list = map.entries.where((e) => e.value > 0).map((e) => CategoryShare(e.key, e.value)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  static List<StockItem> alerts(List<StockItem> items) {
    final list = items.where((i) => i.status.isAlert).toList()
      ..sort((a, b) {
        final s = a.status.index.compareTo(b.status.index);
        return s != 0 ? s : a.stock.compareTo(b.stock);
      });
    return list;
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
