import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'models.dart';

part 'shop_repository_v4.dart';

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
      final barcode = _clean(p.barcode);
      if (barcode != null) {
        final other = await _productByBarcode(txn, userId, barcode);
        if (other != null && other != p.id) throw const BusinessException('Ce code-barres est déjà attribué à un autre produit');
      }

      final values = <String, Object?>{
        'reference': reference,
        'name': name,
        'categoryId': p.categoryId,
        'unit': p.unit.trim().isEmpty ? 'unité' : p.unit.trim(),
        'alertThreshold': p.alertThreshold,
        'sellingPrice': p.sellingPrice,
        'barcode': barcode,
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
      COALESCE(SUM(CASE WHEN m.type = 'OUT' THEN m.quantity * (m.unitPrice - m.unitCost) END), 0) AS profit,
      COALESCE(SUM(CASE WHEN m.type = 'LOSS' THEN m.quantity END), 0) AS qtyLoss,
      COALESCE(SUM(CASE WHEN m.type = 'LOSS' THEN m.quantity * m.unitCost END), 0) AS valueLoss
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
    qtyLoss: (r['qtyLoss'] as num).toInt(),
    valueLoss: (r['valueLoss'] as num).toDouble(),
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

  /// Enregistre un mouvement d'un seul produit :
  /// - entrée (achat fournisseur) au coût d'achat saisi ;
  /// - perte (casse, vol, périmé...) valorisée au CUMP ;
  /// - vente : crée un ticket d'une ligne, payé comptant (voir [recordSale]).
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
    if (type == MovementType.sale) {
      final item = await stockItem(userId, productId);
      if (item == null) throw const BusinessException('Produit introuvable');
      final detail = await recordSale(
        userId: userId,
        lines: [SaleLine(item: item, quantity: quantity, unitPrice: unitPrice)],
        date: date,
        client: partner,
        paid: quantity * unitPrice,
        note: note,
      );
      return detail.lines.first;
    }
    _checkQuantityAndDate(quantity, date);
    if (unitPrice < 0) throw const BusinessException('Le prix ne peut pas être négatif');
    if (type == MovementType.entry && unitPrice == 0) {
      throw const BusinessException('Le coût d\'achat doit être supérieur à 0');
    }
    if (type == MovementType.loss && (note == null || note.trim().length < 3)) {
      throw const BusinessException('Indiquez la raison de la perte');
    }

    final id = await db.transaction<int>((txn) async {
      final item = await _activeItem(txn, userId, productId);
      if (type == MovementType.loss) _checkStock(item, quantity);
      final number = await _nextNumber(txn, 'movements', userId, type: type.code);
      // Une perte est valorisée au CUMP du moment (elle ne modifie pas le CUMP).
      final cost = type == MovementType.loss ? item.cump : unitPrice;
      final newId = await txn.insert('movements', {
        'userId': userId,
        'productId': productId,
        'type': type.code,
        'number': number,
        'date': iso(date),
        'quantity': quantity,
        'unitPrice': cost,
        'unitCost': cost,
        'partner': _clean(partner),
        'note': _clean(note),
        'createdAt': _now(),
      });
      await audit(
        userId,
        type.label,
        '${type.prefix}-$number ${item.product.reference} x$quantity à ${cost.round()} FCFA'
        '${type == MovementType.loss ? ' (${note!.trim()})' : ''}',
        executor: txn,
      );
      return newId;
    });
    _changed();
    return (await movements(userId, movementId: id)).first;
  }

  /// Vente d'un ou plusieurs articles en une seule transaction (ticket de caisse).
  /// [paid] = somme encaissée maintenant. Si elle est inférieure au total, le reste
  /// devient un crédit au nom du client (obligatoire dans ce cas).
  Future<TicketDetail> recordSale({
    required int userId,
    required List<SaleLine> lines,
    required DateTime date,
    String? client,
    required double paid,
    String method = 'Espèces',
    String? note,
    int? priceLevelId,
    int? quoteId,
  }) async {
    if (lines.isEmpty) throw const BusinessException('Le panier est vide');
    for (final l in lines) {
      _checkQuantityAndDate(l.quantity, date);
      if (l.unitPrice < 0) throw const BusinessException('Le prix ne peut pas être négatif');
    }
    final total = lines.fold<double>(0, (s, l) => s + l.total);
    if (paid < 0) throw const BusinessException('Le montant encaissé ne peut pas être négatif');
    final cashed = paid > total ? total : paid;
    final who = _clean(client);
    if (total - cashed >= 1 && who == null) {
      throw const BusinessException('Vente à crédit : indiquez le nom du client');
    }

    final ticketId = await db.transaction<int>((txn) async {
      // Contrôle du stock produit par produit (un produit peut apparaître sur plusieurs lignes).
      final wanted = <int, int>{};
      for (final l in lines) {
        wanted[l.item.product.id!] = (wanted[l.item.product.id!] ?? 0) + l.quantity;
      }
      final items = <int, StockItem>{};
      for (final e in wanted.entries) {
        final item = await _activeItem(txn, userId, e.key);
        _checkStock(item, e.value);
        items[e.key] = item;
      }

      // Fiche client créée au besoin ; plafond de crédit vérifié.
      if (who != null) {
        final client = await _ensureClient(txn, userId, who);
        final credit = total - cashed;
        if (credit >= 1 && client.creditLimit > 0) {
          final owed = await _clientBalance(txn, userId, who);
          if (owed + credit > client.creditLimit + 0.5) {
            throw BusinessException(
              'Plafond de crédit dépassé pour $who : il doit déjà ${Fmt.money(owed)}, '
              'plafond ${Fmt.money(client.creditLimit)}.',
            );
          }
        }
      }

      final ticketNumber = await _nextNumber(txn, 'tickets', userId);
      final tId = await txn.insert('tickets', {
        'userId': userId,
        'number': ticketNumber,
        'date': iso(date),
        'client': who,
        'note': _clean(note),
        'priceLevelId': priceLevelId,
        'createdAt': _now(),
      });
      if (quoteId != null) {
        final n = await txn.update(
          'quotes',
          {'status': QuoteStatus.converted.code, 'ticketId': tId},
          where: 'id = ? AND userId = ? AND status = ?',
          whereArgs: [quoteId, userId, QuoteStatus.open.code],
        );
        if (n == 0) throw const BusinessException('Ce devis a déjà été transformé ou annulé');
      }
      var number = await _nextNumber(txn, 'movements', userId, type: 'OUT');
      for (final l in lines) {
        final item = items[l.item.product.id!]!;
        await txn.insert('movements', {
          'userId': userId,
          'productId': item.product.id,
          'type': 'OUT',
          'number': number++,
          'date': iso(date),
          'quantity': l.quantity,
          'unitPrice': l.unitPrice,
          // CUMP figé au moment de la vente : le bénéfice ne change plus ensuite.
          'unitCost': item.cump,
          'partner': who,
          'note': _clean(note),
          'ticketId': tId,
          'packName': PackMath.isPack(l.packSize) ? l.packName : null,
          'packSize': PackMath.isPack(l.packSize) ? l.packSize : null,
          'createdAt': _now(),
        });
      }
      if (cashed > 0) {
        await txn.insert('payments', {
          'userId': userId,
          'ticketId': tId,
          'amount': cashed,
          'date': iso(date),
          'method': method,
          'createdAt': _now(),
        });
      }
      final credit = total - cashed;
      await audit(
        userId,
        'Vente',
        'T-$ticketNumber : ${Fmt.count(lines.length, 'article')}, ${total.round()} FCFA'
            '${credit >= 1 ? ', crédit ${credit.round()} FCFA ($who)' : ''}',
        executor: txn,
      );
      return tId;
    });
    _changed();
    return (await ticketDetail(userId, ticketId))!;
  }

  /// Inventaire physique : aligne le stock sur la quantité comptée.
  /// Manquant → perte ; surplus → entrée au CUMP (le CUMP ne bouge pas).
  /// Retourne le mouvement créé, ou null si le stock était déjà juste.
  Future<Movement?> adjustStockToCount({
    required int userId,
    required int productId,
    required int counted,
    required String reason,
  }) async {
    if (counted < 0) throw const BusinessException('La quantité comptée ne peut pas être négative');
    final item = await stockItem(userId, productId);
    if (item == null) throw const BusinessException('Produit introuvable');
    final diff = counted - item.stock;
    if (diff == 0) return null;
    final why = reason.trim().isEmpty ? 'écart constaté' : reason.trim();
    if (diff < 0) {
      return recordMovement(
        userId: userId,
        type: MovementType.loss,
        productId: productId,
        quantity: -diff,
        unitPrice: item.cump,
        date: DateTime.now(),
        note: 'Inventaire : $why',
      );
    }
    final cost = item.cump > 0 ? item.cump : item.product.initialUnitCost;
    if (cost <= 0) {
      throw const BusinessException('Coût inconnu pour ce produit : faites plutôt une entrée avec son coût d\'achat');
    }
    return recordMovement(
      userId: userId,
      type: MovementType.entry,
      productId: productId,
      quantity: diff,
      unitPrice: cost,
      date: DateTime.now(),
      partner: 'Inventaire',
      note: 'Surplus d\'inventaire : $why',
    );
  }

  void _checkQuantityAndDate(int quantity, DateTime date) {
    if (quantity <= 0) throw const BusinessException('La quantité doit être supérieure à 0');
    if (date.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      throw const BusinessException('La date ne peut pas être dans le futur');
    }
  }

  Future<StockItem> _activeItem(DatabaseExecutor txn, int userId, int productId) async {
    final item = await stockItem(userId, productId, executor: txn);
    if (item == null) throw const BusinessException('Produit introuvable');
    if (item.product.archived) throw BusinessException('${item.product.name} est archivé');
    return item;
  }

  void _checkStock(StockItem item, int quantity) {
    if (quantity > item.stock) {
      throw BusinessException(
        'Stock insuffisant pour ${item.product.name} : '
        '${Fmt.qtyUnit(item.stock < 0 ? 0 : item.stock, item.product.unit)} en stock',
      );
    }
  }

  Future<int> _nextNumber(DatabaseExecutor txn, String table, int userId, {String? type}) async {
    final r = await txn.rawQuery(
      'SELECT COALESCE(MAX(number), 0) + 1 AS n FROM $table WHERE userId = ?${type != null ? ' AND type = ?' : ''}',
      [userId, if (type != null) type],
    );
    return (r.first['n'] as num).toInt();
  }

  /// Annule un mouvement (il reste visible, barré, dans l'historique).
  /// Retourne la somme à rendre au client si la ligne annulée était déjà payée (sinon 0).
  Future<double> cancelMovement(int userId, int movementId, String reason) async {
    final why = reason.trim();
    if (why.length < 3) throw const BusinessException('Indiquez le motif de l\'annulation');
    var refund = 0.0;
    await db.transaction((txn) async {
      final rows = await txn.query('movements', where: 'id = ? AND userId = ?', whereArgs: [movementId, userId]);
      if (rows.isEmpty) throw const BusinessException('Opération introuvable');
      final m = rows.first;
      if ((m['cancelled'] as int) == 1) throw const BusinessException('Opération déjà annulée');
      final type = MovementType.fromCode(m['type'] as String);
      if (type == MovementType.entry) {
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
      await audit(userId, 'Annulation', '${type.prefix}-${m['number']} annulée : $why', executor: txn);

      // Ligne d'un ticket déjà payé : le trop-perçu est rendu au client.
      final ticketId = m['ticketId'] as int?;
      if (ticketId != null) {
        final t = await _ticketRow(txn, userId, ticketId);
        final overpaid = t.paid - t.total;
        if (overpaid >= 1) {
          await txn.insert('payments', {
            'userId': userId,
            'ticketId': ticketId,
            'amount': -overpaid,
            'date': _now(),
            'method': 'Remboursement',
            'note': 'Annulation ${type.prefix}-${m['number']}',
            'createdAt': _now(),
          });
          await audit(
            userId,
            'Remboursement',
            '${t.code} : ${overpaid.round()} FCFA rendus au client${t.client != null ? ' (${t.client})' : ''}',
            executor: txn,
          );
          refund = overpaid;
        }
      }
    });
    _changed();
    return refund;
  }

  Future<List<Movement>> movements(
    int userId, {
    int? movementId,
    int? ticketId,
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
    if (ticketId != null) {
      where.add('m.ticketId = ?');
      args.add(ticketId);
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
      SELECT m.*, p.reference, p.name AS productName, p.unit, c.name AS categoryName, t.number AS ticketNumber
      FROM movements m
      JOIN products p ON p.id = m.productId
      LEFT JOIN categories c ON c.id = p.categoryId
      LEFT JOIN tickets t ON t.id = m.ticketId
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
        COUNT(DISTINCT CASE WHEN m.type = 'OUT' THEN COALESCE(m.ticketId, -m.id) END) AS salesCount,
        COALESCE(SUM(CASE WHEN m.type = 'LOSS' THEN m.quantity END), 0) AS qtyLoss,
        COALESCE(SUM(CASE WHEN m.type = 'LOSS' THEN m.quantity * m.unitCost END), 0) AS valueLoss,
        COALESCE(SUM(CASE WHEN m.type = 'OUT' AND m.ticketId IS NULL THEN m.quantity * m.unitPrice END), 0) AS legacyCash
      FROM movements m JOIN products p ON p.id = m.productId
      WHERE m.userId = ? AND m.cancelled = 0 $filter
    ''', args)).first;
    // Encaissements de la période (toutes catégories : un paiement couvre tout un ticket).
    var cashIn = (r['legacyCash'] as num).toDouble();
    if (categoryId == null) {
      final pArgs = <Object?>[userId];
      final pFilter = StringBuffer();
      if (from != null) {
        pFilter.write(' AND date >= ?');
        pArgs.add(iso(from));
      }
      if (to != null) {
        pFilter.write(' AND date < ?');
        pArgs.add(iso(to));
      }
      final pr = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM payments WHERE userId = ? AND cancelled = 0$pFilter',
        pArgs,
      );
      cashIn += (pr.first['s'] as num).toDouble();
    }
    return PeriodSummary(
      qtyIn: (r['qtyIn'] as num).toInt(),
      valueIn: (r['valueIn'] as num).toDouble(),
      qtyOut: (r['qtyOut'] as num).toInt(),
      salesAmount: (r['salesAmount'] as num).toDouble(),
      profit: (r['profit'] as num).toDouble(),
      salesCount: (r['salesCount'] as num).toInt(),
      qtyLoss: (r['qtyLoss'] as num).toInt(),
      valueLoss: (r['valueLoss'] as num).toDouble(),
      cashIn: cashIn,
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

  // ======================================================================
  // Tickets de caisse, encaissements et crédits clients
  // ======================================================================

  static const _ticketSql = '''
    SELECT t.*,
      COALESCE((SELECT SUM(m.quantity * m.unitPrice) FROM movements m
                WHERE m.ticketId = t.id AND m.cancelled = 0), 0) AS total,
      COALESCE((SELECT SUM(p.amount) FROM payments p
                WHERE p.ticketId = t.id AND p.cancelled = 0), 0) AS paid,
      (SELECT COUNT(*) FROM movements m WHERE m.ticketId = t.id AND m.cancelled = 0) AS lineCount
    FROM tickets t
  ''';

  Future<Ticket> _ticketRow(DatabaseExecutor ex, int userId, int ticketId) async {
    final rows = await ex.rawQuery('$_ticketSql WHERE t.userId = ? AND t.id = ?', [userId, ticketId]);
    if (rows.isEmpty) throw const BusinessException('Ticket introuvable');
    return Ticket.fromMap(rows.first);
  }

  Future<TicketDetail?> ticketDetail(int userId, int ticketId) async {
    final rows = await db.rawQuery('$_ticketSql WHERE t.userId = ? AND t.id = ?', [userId, ticketId]);
    if (rows.isEmpty) return null;
    final lines = await movements(userId, ticketId: ticketId);
    final pays = await db.rawQuery(
      'SELECT p.*, t.number AS ticketNumber FROM payments p JOIN tickets t ON t.id = p.ticketId '
      'WHERE p.userId = ? AND p.ticketId = ? ORDER BY p.date, p.id',
      [userId, ticketId],
    );
    return TicketDetail(Ticket.fromMap(rows.first), lines.reversed.toList(), pays.map(Payment.fromMap).toList());
  }

  /// Derniers tickets, du plus récent au plus ancien.
  Future<List<Ticket>> tickets(int userId, {int limit = 200, String? search}) async {
    final q = search?.trim() ?? '';
    final rows = await db.rawQuery(
      '$_ticketSql WHERE t.userId = ? ${q.isEmpty ? '' : 'AND (t.client LIKE ? OR t.number = ?)'} '
      'ORDER BY t.date DESC, t.id DESC LIMIT $limit',
      [userId, if (q.isNotEmpty) '%$q%', if (q.isNotEmpty) int.tryParse(q.replaceAll(RegExp(r'\D'), '')) ?? -1],
    );
    return rows.map(Ticket.fromMap).toList();
  }

  /// Tickets non soldés (crédits), du plus ancien au plus récent.
  Future<List<Ticket>> openTickets(int userId, {String? client}) async {
    final rows = await db.rawQuery(
      '$_ticketSql WHERE t.userId = ? ${client != null ? 'AND t.client = ? COLLATE NOCASE' : ''} '
      'ORDER BY t.date, t.id',
      [userId, if (client != null) client],
    );
    return rows.map(Ticket.fromMap).where((t) => t.isCredit).toList();
  }

  /// Ce que chaque client doit encore, du plus gros montant au plus petit.
  Future<List<ClientDebt>> clientDebts(int userId) async {
    final open = await openTickets(userId);
    final byClient = <String, List<Ticket>>{};
    for (final t in open) {
      final key = (t.client ?? 'Client inconnu').trim();
      byClient.putIfAbsent(key.toLowerCase(), () => []).add(t);
    }
    final list =
        byClient.values
            .map(
              (ts) => ClientDebt(
                client: ts.first.client ?? 'Client inconnu',
                balance: ts.fold(0, (s, t) => s + t.balance),
                ticketCount: ts.length,
                oldest: ts.first.date,
              ),
            )
            .toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
    return list;
  }

  /// Encaisse un paiement sur un ticket précis (acompte ou solde).
  Future<void> addPayment(
    int userId,
    int ticketId,
    double amount, {
    String method = 'Espèces',
    String? note,
    DateTime? date,
  }) async {
    if (amount <= 0) throw const BusinessException('Le montant doit être supérieur à 0');
    await db.transaction((txn) async {
      final t = await _ticketRow(txn, userId, ticketId);
      if (amount > t.balance + 0.5) {
        throw BusinessException('Le client ne doit que ${Fmt.money(t.balance < 0 ? 0 : t.balance)} sur ce ticket');
      }
      await txn.insert('payments', {
        'userId': userId,
        'ticketId': ticketId,
        'amount': amount,
        'date': iso(date ?? DateTime.now()),
        'method': method,
        'note': _clean(note),
        'createdAt': _now(),
      });
      await audit(
        userId,
        'Encaissement',
        '${t.code} : ${amount.round()} FCFA ($method)${t.client != null ? ' — ${t.client}' : ''}',
        executor: txn,
      );
    });
    _changed();
  }

  /// Remboursement d'un client : la somme est répartie sur ses tickets, du plus ancien au plus récent.
  Future<void> payClientDebt(int userId, String client, double amount, {String method = 'Espèces'}) async {
    if (amount <= 0) throw const BusinessException('Le montant doit être supérieur à 0');
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '$_ticketSql WHERE t.userId = ? AND t.client = ? COLLATE NOCASE ORDER BY t.date, t.id',
        [userId, client],
      );
      final open = rows.map(Ticket.fromMap).where((t) => t.isCredit).toList();
      final due = open.fold<double>(0, (s, t) => s + t.balance);
      if (open.isEmpty) throw BusinessException('$client n\'a aucun crédit en cours');
      if (amount > due + 0.5) throw BusinessException('$client ne doit que ${Fmt.money(due)}');
      var rest = amount;
      for (final t in open) {
        if (rest <= 0) break;
        final part = rest < t.balance ? rest : t.balance;
        await txn.insert('payments', {
          'userId': userId,
          'ticketId': t.id,
          'amount': part,
          'date': _now(),
          'method': method,
          'createdAt': _now(),
        });
        rest -= part;
      }
      await audit(userId, 'Encaissement', '$client rembourse ${amount.round()} FCFA ($method)', executor: txn);
    });
    _changed();
  }

  /// Annule un encaissement saisi par erreur (il reste visible dans le ticket).
  Future<void> cancelPayment(int userId, int paymentId) async {
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT p.*, t.number AS ticketNumber FROM payments p JOIN tickets t ON t.id = p.ticketId '
        'WHERE p.id = ? AND p.userId = ?',
        [paymentId, userId],
      );
      if (rows.isEmpty) throw const BusinessException('Encaissement introuvable');
      final p = Payment.fromMap(rows.first);
      if (p.cancelled) throw const BusinessException('Encaissement déjà annulé');
      await txn.update('payments', {'cancelled': 1}, where: 'id = ?', whereArgs: [paymentId]);
      await audit(
        userId,
        'Annulation',
        'Encaissement de ${p.amount.round()} FCFA annulé (T-${p.ticketNumber})',
        executor: txn,
      );
    });
    _changed();
  }

  /// Total des crédits clients en cours.
  Future<double> totalCredit(int userId) async => (await openTickets(userId)).fold<double>(0, (s, t) => s + t.balance);

  /// Clients déjà servis (auto-complétion).
  Future<List<String>> clients(int userId) async {
    final rows = await db.rawQuery(
      '''
      SELECT name, MAX(last) AS last FROM (
        SELECT client AS name, date AS last FROM tickets
        WHERE userId = ? AND client IS NOT NULL AND client <> ''
        UNION ALL
        SELECT name, createdAt AS last FROM clients WHERE userId = ?
      ) GROUP BY name COLLATE NOCASE ORDER BY last DESC LIMIT 300
    ''',
      [userId, userId],
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Achats par fournisseur sur une période (comparaison des fournisseurs).
  Future<List<CategoryShare>> purchasesBySupplier(int userId, {DateTime? from, DateTime? to}) async {
    final args = <Object?>[userId];
    final filter = _periodFilter(args, from, to, null);
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(m.partner), ''), 'Fournisseur non précisé') AS supplier,
             SUM(m.quantity * m.unitPrice) AS total
      FROM movements m JOIN products p ON p.id = m.productId
      WHERE m.userId = ? AND m.type = 'IN' AND m.cancelled = 0
        AND COALESCE(m.partner, '') <> 'Inventaire' $filter
      GROUP BY supplier COLLATE NOCASE ORDER BY total DESC
    ''', args);
    return rows.map((r) => CategoryShare(r['supplier'] as String, (r['total'] as num).toDouble())).toList();
  }

  // ======================================================================
  // Code de secours (mot de passe oublié)
  // ======================================================================

  Future<void> setRecoveryHash(int userId, String hash) =>
      db.update('users', {'recoveryHash': hash}, where: 'id = ?', whereArgs: [userId]);

  // ======================================================================
  // Sauvegarde / restauration
  // ======================================================================

  static const backupFormat = 'shopbook-backup';
  /// v2 : + profil, tarifs, conditionnements, clients, devis.
  static const backupVersion = 2;

  /// Exporte toutes les données de la boutique (sans le mot de passe).
  Future<Map<String, Object?>> exportData(int userId) async {
    final user = await findUserRowById(userId);
    if (user == null) throw const BusinessException('Compte introuvable');
    Future<List<Map<String, Object?>>> all(String table) =>
        db.query(table, where: 'userId = ?', whereArgs: [userId], orderBy: 'id');
    return {
      'format': backupFormat,
      'version': backupVersion,
      'exportedAt': _now(),
      'shop': {
        'name': user['name'],
        'businessName': user['businessName'],
        'defaultAlertThreshold': user['defaultAlertThreshold'],
        'warningColor': user['warningColor'],
        'criticalColor': user['criticalColor'],
      },
      'categories': await all('categories'),
      'products': await all('products'),
      'tickets': await all('tickets'),
      'movements': await all('movements'),
      'payments': await all('payments'),
      'profile': (await db.query('shop_profile', where: 'userId = ?', whereArgs: [userId])).firstOrNull,
      'priceLevels': await all('price_levels'),
      'productPrices': await db.rawQuery(
        'SELECT pp.* FROM product_prices pp JOIN products p ON p.id = pp.productId WHERE p.userId = ?',
        [userId],
      ),
      'productPacks': await db.rawQuery(
        'SELECT pk.* FROM product_packs pk JOIN products p ON p.id = pk.productId WHERE p.userId = ? ORDER BY pk.id',
        [userId],
      ),
      'clients': await all('clients'),
      'quotes': await all('quotes'),
      'quoteLines': await db.rawQuery(
        'SELECT l.* FROM quote_lines l JOIN quotes q ON q.id = l.quoteId WHERE q.userId = ? ORDER BY l.id',
        [userId],
      ),
    };
  }

  /// Remplace les données de la boutique par celles d'une sauvegarde.
  /// Les identifiants sont renumérotés ; l'historique est conservé à l'identique.
  Future<void> importData(int userId, Map<String, Object?> data) async {
    if (data['format'] != backupFormat || data['version'] is! int || (data['version'] as int) > backupVersion) {
      throw const BusinessException('Ce fichier n\'est pas une sauvegarde ShopBook valide');
    }
    List<Map<String, Object?>> list(String key) {
      final v = data[key];
      if (v is! List) throw BusinessException('Sauvegarde incomplète ($key manquant)');
      return v.cast<Map<String, Object?>>();
    }

    final categories = list('categories');
    final products = list('products');
    final tickets = list('tickets');
    final movements = list('movements');
    final payments = list('payments');
    // Sauvegardes v1 : pas encore de tarifs, clients ni devis.
    List<Map<String, Object?>> optional(String key) => data[key] is List ? list(key) : const [];
    final levels = optional('priceLevels');
    final productPrices = optional('productPrices');
    final productPacks = optional('productPacks');
    final clients = optional('clients');
    final quotes = optional('quotes');
    final quoteLines = optional('quoteLines');
    final profile = data['profile'] is Map ? (data['profile'] as Map).cast<String, Object?>() : null;

    await db.transaction((txn) async {
      // quote_lines, product_prices et product_packs suivent par ON DELETE CASCADE.
      for (final t in ['quotes', 'clients', 'payments', 'movements', 'tickets', 'products', 'price_levels', 'categories']) {
        await txn.delete(t, where: 'userId = ?', whereArgs: [userId]);
      }
      await txn.delete('shop_profile', where: 'userId = ?', whereArgs: [userId]);
      Map<String, Object?> strip(Map<String, Object?> row, List<String> drop) =>
          Map.of(row)..removeWhere((k, _) => drop.contains(k));

      final catIds = <Object?, int>{};
      for (final c in categories) {
        catIds[c['id']] = await txn.insert('categories', {
          ...strip(c, ['id']),
          'userId': userId,
        });
      }
      final productIds = <Object?, int>{};
      for (final p in products) {
        productIds[p['id']] = await txn.insert('products', {
          ...strip(p, ['id']),
          'userId': userId,
          'categoryId': p['categoryId'] == null ? null : catIds[p['categoryId']],
        });
      }
      final levelIds = <Object?, int>{};
      for (final l in levels) {
        levelIds[l['id']] = await txn.insert('price_levels', {...strip(l, ['id']), 'userId': userId});
      }
      for (final pp in productPrices) {
        final pid = productIds[pp['productId']], lid = levelIds[pp['levelId']];
        if (pid != null && lid != null) {
          await txn.insert('product_prices', {
            'productId': pid,
            'levelId': lid,
            'price': pp['price'],
            'minQty': pp['minQty'] ?? 0,
          });
        }
      }
      for (final pk in productPacks) {
        final pid = productIds[pk['productId']];
        if (pid != null) await txn.insert('product_packs', {...strip(pk, ['id']), 'productId': pid});
      }
      if (profile != null) await txn.insert('shop_profile', {...profile, 'userId': userId});
      for (final c in clients) {
        await txn.insert('clients', {
          ...strip(c, ['id']),
          'userId': userId,
          'priceLevelId': levelIds[c['priceLevelId']],
        });
      }
      final ticketIds = <Object?, int>{};
      for (final t in tickets) {
        ticketIds[t['id']] = await txn.insert('tickets', {
          ...strip(t, ['id']),
          'userId': userId,
          if (t.containsKey('priceLevelId')) 'priceLevelId': levelIds[t['priceLevelId']],
        });
      }
      final quoteIds = <Object?, int>{};
      for (final q in quotes) {
        quoteIds[q['id']] = await txn.insert('quotes', {
          ...strip(q, ['id']),
          'userId': userId,
          'ticketId': ticketIds[q['ticketId']],
        });
      }
      for (final l in quoteLines) {
        final qid = quoteIds[l['quoteId']], pid = productIds[l['productId']];
        if (qid != null && pid != null) {
          await txn.insert('quote_lines', {...strip(l, ['id']), 'quoteId': qid, 'productId': pid});
        }
      }
      for (final m in movements) {
        final pid = productIds[m['productId']];
        if (pid == null) throw const BusinessException('Sauvegarde corrompue : produit manquant');
        await txn.insert('movements', {
          ...strip(m, ['id']),
          'userId': userId,
          'productId': pid,
          'ticketId': m['ticketId'] == null ? null : ticketIds[m['ticketId']],
        });
      }
      for (final p in payments) {
        final tid = ticketIds[p['ticketId']];
        if (tid == null) throw const BusinessException('Sauvegarde corrompue : ticket manquant');
        await txn.insert('payments', {
          ...strip(p, ['id']),
          'userId': userId,
          'ticketId': tid,
        });
      }
      await audit(
        userId,
        'Sauvegarde',
        'Restauration : ${Fmt.count(products.length, 'produit')}, ${Fmt.count(movements.length, 'opération')}',
        executor: txn,
      );
    });
    _changed();
  }

  /// Export CSV (séparateur « ; », lisible directement par Excel en français).
  Future<String> inventoryCsv(int userId) async {
    final items = await inventory(userId, includeArchived: true);
    final b = StringBuffer(
      'Référence;Désignation;Catégorie;Unité;Seuil;Stock initial;Entrées;Sorties;Pertes;Stock final;CUMP;Valeur;Prix de vente;Statut;Archivé\n',
    );
    for (final i in items) {
      b.writeln(
        [
          i.product.reference,
          i.product.name,
          i.categoryName ?? '',
          i.product.unit,
          i.product.alertThreshold,
          i.product.initialStock,
          i.qtyIn,
          i.qtyOut,
          i.qtyLoss,
          i.stock,
          i.cump.round(),
          i.stockValue.round(),
          i.product.sellingPrice.round(),
          i.status.label,
          i.product.archived ? 'oui' : 'non',
        ].map(_csv).join(';'),
      );
    }
    return b.toString();
  }

  Future<String> movementsCsv(int userId, {DateTime? from, DateTime? to}) async {
    final list = await movements(userId, from: from, to: to);
    final b = StringBuffer(
      'N°;Type;Date;Référence;Désignation;Quantité;Prix unitaire;Total;CUMP;Bénéfice;Client/Fournisseur;Ticket;Note;Annulée;Motif\n',
    );
    for (final m in list.reversed) {
      b.writeln(
        [
          m.code,
          m.type.label,
          _isoFmt.format(m.date).replaceFirst('T', ' '),
          m.productReference,
          m.productName,
          m.quantity,
          m.unitPrice.round(),
          m.total.round(),
          m.unitCost.round(),
          m.profit.round(),
          m.partner ?? '',
          m.ticketNumber == null ? '' : 'T-${m.ticketNumber}',
          m.note ?? '',
          m.cancelled ? 'oui' : 'non',
          m.cancelReason ?? '',
        ].map(_csv).join(';'),
      );
    }
    return b.toString();
  }

  static String _csv(Object? v) {
    final s = '${v ?? ''}';
    return s.contains(RegExp('[;"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
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
