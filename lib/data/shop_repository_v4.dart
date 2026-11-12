part of 'shop_repository.dart';

/// v4 : boutique paramétrable — profil, tarifs, conditionnements, codes-barres,
/// clients, factures numérotées et devis.
extension ShopRepositoryV4 on ShopRepository {
  // ======================================================================
  // Profil de la boutique
  // ======================================================================

  Future<ShopProfile> shopProfile(int userId) async {
    final rows = await db.query('shop_profile', where: 'userId = ?', whereArgs: [userId]);
    return rows.isEmpty ? const ShopProfile() : ShopProfile.fromMap(rows.first);
  }

  Future<void> saveShopProfile(int userId, ShopProfile p) async {
    if (p.vatRate < 0 || p.vatRate >= 100) throw const BusinessException('Taux de TVA invalide');
    String? c(String? s) => ShopRepository._clean(s);
    final values = {
      ...p.toMap(),
      'activity': c(p.activity),
      'address': c(p.address),
      'city': c(p.city),
      'phone': c(p.phone),
      'niu': c(p.niu)?.toUpperCase(),
      'rccm': c(p.rccm)?.toUpperCase(),
      'invoiceFooter': c(p.invoiceFooter),
    };
    final before = await shopProfile(userId);
    await db.transaction((txn) async {
      await txn.insert('shop_profile', {...values, 'userId': userId}, conflictAlgorithm: ConflictAlgorithm.replace);
      if (before.shopType != p.shopType) await _applyShopTypePreset(txn, userId, p.shopType);
      await audit(userId, 'Réglages', 'Profil de la boutique (${p.shopType.label})', executor: txn);
    });
    _changed();
  }

  /// Tarifs proposés selon le type de commerce. N'efface jamais rien :
  /// ajoute seulement les tarifs manquants, que le commerçant peut renommer ou supprimer.
  Future<void> _applyShopTypePreset(DatabaseExecutor txn, int userId, ShopType type) async {
    final wanted = switch (type) {
      ShopType.retail => const <(String, int)>[],
      ShopType.wholesale => const [('Gros', 0)],
      ShopType.hybrid => const [('Demi-gros', 6), ('Gros', 12)],
    };
    var position = 1;
    for (final (name, minQty) in wanted) {
      await txn.insert('price_levels', {
        'userId': userId,
        'name': name,
        'minQty': minQty,
        'position': position++,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // ======================================================================
  // Tarifs (grilles de prix)
  // ======================================================================

  Future<List<PriceLevel>> priceLevels(int userId) async {
    final rows = await db.query('price_levels', where: 'userId = ?', whereArgs: [userId], orderBy: 'position, id');
    return rows.map(PriceLevel.fromMap).toList();
  }

  Future<int> savePriceLevel(int userId, {int? id, required String name, int minQty = 0}) async {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) throw const BusinessException('Le nom du tarif est obligatoire');
    if (n.toLowerCase() == Pricing.retailName.toLowerCase()) {
      throw const BusinessException('« Détail » est le prix de base de chaque produit : choisissez un autre nom');
    }
    if (minQty < 0) throw const BusinessException('Le palier ne peut pas être négatif');
    final clash = await db.query(
      'price_levels',
      where: 'userId = ? AND name = ? AND id <> ?',
      whereArgs: [userId, n, id ?? -1],
    );
    if (clash.isNotEmpty) throw BusinessException('Le tarif « $n » existe déjà');
    late int levelId;
    if (id == null) {
      final pos = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COALESCE(MAX(position), 0) + 1 FROM price_levels WHERE userId = ?', [userId]),
          ) ??
          1;
      levelId = await db.insert('price_levels', {'userId': userId, 'name': n, 'minQty': minQty, 'position': pos});
      await audit(userId, 'Tarif', 'Ajout du tarif « $n »');
    } else {
      levelId = id;
      await db.update(
        'price_levels',
        {'name': n, 'minQty': minQty},
        where: 'id = ? AND userId = ?',
        whereArgs: [id, userId],
      );
      await audit(userId, 'Tarif', 'Modification du tarif « $n »');
    }
    _changed();
    return levelId;
  }

  Future<void> deletePriceLevel(int userId, int levelId) async {
    await db.delete('price_levels', where: 'id = ? AND userId = ?', whereArgs: [levelId, userId]);
    await audit(userId, 'Tarif', 'Suppression du tarif #$levelId');
    _changed();
  }

  // ======================================================================
  // Tarifs et conditionnements par produit
  // ======================================================================

  Future<ProductPricing> productPricing(int productId) async => (await _pricingWhere('p.id = ?', [productId]))[productId] ?? ProductPricing.empty;

  /// Tarifs et conditionnements de tous les produits de la boutique (panier, stock).
  Future<Map<int, ProductPricing>> allPricing(int userId) => _pricingWhere('p.userId = ?', [userId]);

  Future<Map<int, ProductPricing>> _pricingWhere(String where, List<Object?> args) async {
    final prices = await db.rawQuery(
      'SELECT pp.* FROM product_prices pp JOIN products p ON p.id = pp.productId WHERE $where',
      args,
    );
    final packs = await db.rawQuery(
      'SELECT pk.* FROM product_packs pk JOIN products p ON p.id = pk.productId WHERE $where ORDER BY pk.quantity',
      args,
    );
    final levelPrices = <int, Map<int, double>>{};
    final levelMin = <int, Map<int, int>>{};
    final packList = <int, List<ProductPack>>{};
    for (final r in prices) {
      final pid = r['productId'] as int;
      (levelPrices[pid] ??= {})[r['levelId'] as int] = (r['price'] as num).toDouble();
      (levelMin[pid] ??= {})[r['levelId'] as int] = r['minQty'] as int;
    }
    for (final r in packs) {
      (packList[r['productId'] as int] ??= []).add(ProductPack.fromMap(r));
    }
    final ids = {...levelPrices.keys, ...packList.keys};
    return {
      for (final id in ids)
        id: ProductPricing(
          levelPrices: levelPrices[id] ?? const {},
          levelMinQty: levelMin[id] ?? const {},
          packs: packList[id] ?? const [],
        ),
    };
  }

  /// Enregistre les prix par tarif (prix 0 = tarif non proposé pour ce produit)
  /// et remplace la liste des conditionnements.
  Future<void> saveProductPricing(
    int userId,
    int productId, {
    required Map<int, ({double price, int minQty})> levelPrices,
    required List<ProductPack> packs,
  }) async {
    final names = <String>{};
    for (final pk in packs) {
      final name = pk.name.trim();
      if (name.isEmpty) throw const BusinessException('Donnez un nom à chaque conditionnement (Carton, Sac…)');
      if (pk.quantity < 2) throw BusinessException('« $name » doit contenir au moins 2 unités');
      if (pk.price < 0) throw const BusinessException('Le prix d\'un conditionnement ne peut pas être négatif');
      if (!names.add(name.toLowerCase())) throw BusinessException('Le conditionnement « $name » est en double');
    }
    for (final e in levelPrices.entries) {
      if (e.value.price < 0 || e.value.minQty < 0) throw const BusinessException('Prix et paliers ne peuvent pas être négatifs');
    }
    await db.transaction((txn) async {
      final own = await txn.query('products', where: 'id = ? AND userId = ?', whereArgs: [productId, userId]);
      if (own.isEmpty) throw const BusinessException('Produit introuvable');
      for (final pk in packs) {
        final code = ShopRepository._clean(pk.barcode);
        if (code == null) continue;
        final other = await _productByBarcode(txn, userId, code);
        if (other != null && other != productId) {
          throw BusinessException('Le code-barres de « ${pk.name} » est déjà attribué à un autre produit');
        }
      }
      await txn.delete('product_prices', where: 'productId = ?', whereArgs: [productId]);
      for (final e in levelPrices.entries) {
        if (e.value.price <= 0) continue;
        await txn.insert('product_prices', {
          'productId': productId,
          'levelId': e.key,
          'price': e.value.price,
          'minQty': e.value.minQty,
        });
      }
      await txn.delete('product_packs', where: 'productId = ?', whereArgs: [productId]);
      for (final pk in packs) {
        await txn.insert('product_packs', {
          'productId': productId,
          'name': pk.name.trim(),
          'quantity': pk.quantity,
          'price': pk.price,
          'barcode': ShopRepository._clean(pk.barcode),
        });
      }
    });
    _changed();
  }

  /// Produit (et conditionnement éventuel) correspondant à un code-barres scanné.
  Future<({int productId, ProductPack? pack})?> findByBarcode(int userId, String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final p = await db.query(
      'products',
      columns: ['id'],
      where: 'userId = ? AND barcode = ? AND archived = 0',
      whereArgs: [userId, c],
    );
    if (p.isNotEmpty) return (productId: p.first['id'] as int, pack: null);
    final pk = await db.rawQuery(
      'SELECT pk.* FROM product_packs pk JOIN products p ON p.id = pk.productId '
      'WHERE p.userId = ? AND pk.barcode = ? AND p.archived = 0',
      [userId, c],
    );
    if (pk.isEmpty) return null;
    return (productId: pk.first['productId'] as int, pack: ProductPack.fromMap(pk.first));
  }

  /// Id du produit qui porte déjà ce code-barres (produit ou conditionnement).
  Future<int?> _productByBarcode(DatabaseExecutor ex, int userId, String code) async {
    final p = await ex.query('products', columns: ['id'], where: 'userId = ? AND barcode = ?', whereArgs: [userId, code]);
    if (p.isNotEmpty) return p.first['id'] as int;
    final pk = await ex.rawQuery(
      'SELECT pk.productId FROM product_packs pk JOIN products p ON p.id = pk.productId '
      'WHERE p.userId = ? AND pk.barcode = ?',
      [userId, code],
    );
    return pk.isEmpty ? null : pk.first['productId'] as int;
  }

  // ======================================================================
  // Clients
  // ======================================================================

  static const _clientSql = '''
    SELECT c.*, COALESCE((
      SELECT SUM(
        COALESCE((SELECT SUM(m.quantity * m.unitPrice) FROM movements m WHERE m.ticketId = t.id AND m.cancelled = 0), 0)
        - COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.ticketId = t.id AND p.cancelled = 0), 0))
      FROM tickets t WHERE t.userId = c.userId AND t.client = c.name COLLATE NOCASE
    ), 0) AS balance
    FROM clients c
  ''';

  Future<List<Client>> clientList(int userId, {String? search}) async {
    final q = search?.trim() ?? '';
    final rows = await db.rawQuery(
      '$_clientSql WHERE c.userId = ? ${q.isEmpty ? '' : 'AND (c.name LIKE ? OR c.phone LIKE ?)'} '
      'ORDER BY c.name COLLATE NOCASE',
      [userId, if (q.isNotEmpty) '%$q%', if (q.isNotEmpty) '%$q%'],
    );
    return rows.map(Client.fromMap).toList();
  }

  Future<Client?> clientByName(int userId, String name) async {
    final rows = await db.rawQuery('$_clientSql WHERE c.userId = ? AND c.name = ? COLLATE NOCASE', [userId, name.trim()]);
    return rows.isEmpty ? null : Client.fromMap(rows.first);
  }

  Future<int> saveClient(int userId, Client c) async {
    final name = c.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const BusinessException('Le nom du client est obligatoire');
    if (c.creditLimit < 0) throw const BusinessException('Le plafond de crédit ne peut pas être négatif');
    final id = await db.transaction<int>((txn) async {
      final clash = await txn.query(
        'clients',
        where: 'userId = ? AND name = ? AND id <> ?',
        whereArgs: [userId, name, c.id ?? -1],
      );
      if (clash.isNotEmpty) throw BusinessException('Le client « $name » existe déjà');
      final values = {
        'name': name,
        'phone': ShopRepository._clean(c.phone),
        'address': ShopRepository._clean(c.address),
        'niu': ShopRepository._clean(c.niu)?.toUpperCase(),
        'priceLevelId': c.priceLevelId,
        'creditLimit': c.creditLimit,
        'note': ShopRepository._clean(c.note),
      };
      if (c.id == null) {
        final newId = await txn.insert('clients', {...values, 'userId': userId, 'createdAt': ShopRepository._now()});
        await audit(userId, 'Client', 'Nouveau client « $name »', executor: txn);
        return newId;
      }
      final old = await txn.query('clients', where: 'id = ? AND userId = ?', whereArgs: [c.id, userId]);
      if (old.isEmpty) throw const BusinessException('Client introuvable');
      final oldName = old.first['name'] as String;
      await txn.update('clients', values, where: 'id = ? AND userId = ?', whereArgs: [c.id, userId]);
      if (oldName != name) {
        // Le nom figure sur les tickets et devis : on le renomme partout.
        await txn.update(
          'tickets',
          {'client': name},
          where: 'userId = ? AND client = ? COLLATE NOCASE',
          whereArgs: [userId, oldName],
        );
        await txn.update(
          'quotes',
          {'client': name},
          where: 'userId = ? AND client = ? COLLATE NOCASE',
          whereArgs: [userId, oldName],
        );
        await txn.update(
          'movements',
          {'partner': name},
          where: "userId = ? AND type = 'OUT' AND partner = ? COLLATE NOCASE",
          whereArgs: [userId, oldName],
        );
      }
      await audit(userId, 'Client', 'Fiche « $name » modifiée', executor: txn);
      return c.id!;
    });
    _changed();
    return id;
  }

  /// Supprime la fiche (l'historique des ventes garde le nom du client).
  Future<void> deleteClient(int userId, int clientId) async {
    final rows = await db.rawQuery('$_clientSql WHERE c.userId = ? AND c.id = ?', [userId, clientId]);
    if (rows.isEmpty) return;
    final c = Client.fromMap(rows.first);
    if (c.balance >= 1) throw BusinessException('${c.name} doit encore ${Fmt.money(c.balance)} : soldez d\'abord son crédit');
    await db.delete('clients', where: 'id = ? AND userId = ?', whereArgs: [clientId, userId]);
    await audit(userId, 'Client', 'Fiche « ${c.name} » supprimée');
    _changed();
  }

  Future<Client> _ensureClient(DatabaseExecutor txn, int userId, String name) async {
    final rows = await txn.query('clients', where: 'userId = ? AND name = ?', whereArgs: [userId, name]);
    if (rows.isNotEmpty) return Client.fromMap(rows.first);
    final id = await txn.insert('clients', {'userId': userId, 'name': name, 'createdAt': ShopRepository._now()});
    return Client(id: id, name: name);
  }

  Future<double> _clientBalance(DatabaseExecutor txn, int userId, String name) async {
    final rows = await txn.rawQuery('$_clientSql WHERE c.userId = ? AND c.name = ? COLLATE NOCASE', [userId, name]);
    return rows.isEmpty ? 0 : ((rows.first['balance'] as num?) ?? 0).toDouble();
  }

  // ======================================================================
  // Factures (numérotation annuelle continue : FAC-2026-0001, 0002…)
  // ======================================================================

  /// Attribue un numéro de facture au ticket (une seule fois : un numéro émis
  /// n'est jamais réutilisé ni modifié). Retourne le ticket à jour.
  Future<Ticket> issueInvoice(int userId, int ticketId, {DateTime? date}) async {
    final ticket = await db.transaction<Ticket>((txn) async {
      final t = await _ticketRow(txn, userId, ticketId);
      if (t.hasInvoice) return t;
      if (t.lineCount == 0) throw const BusinessException('Ce ticket est entièrement annulé : pas de facture possible');
      final d = date ?? DateTime.now();
      final next = (Sqflite.firstIntValue(
                await txn.rawQuery(
                  'SELECT MAX(invoiceNumber) FROM tickets WHERE userId = ? AND invoiceYear = ?',
                  [userId, d.year],
                ),
              ) ??
              0) +
          1;
      await txn.update(
        'tickets',
        {'invoiceYear': d.year, 'invoiceNumber': next, 'invoiceDate': ShopRepository.iso(d)},
        where: 'id = ? AND userId = ?',
        whereArgs: [ticketId, userId],
      );
      final updated = await _ticketRow(txn, userId, ticketId);
      await audit(userId, 'Facture', '${updated.invoiceCode} émise pour ${t.code}', executor: txn);
      return updated;
    });
    _changed();
    return ticket;
  }

  // ======================================================================
  // Devis / factures pro forma
  // ======================================================================

  Future<Quote> createQuote({
    required int userId,
    required List<SaleLine> lines,
    required DateTime date,
    DateTime? validUntil,
    String? client,
    String? note,
  }) async {
    if (lines.isEmpty) throw const BusinessException('Le devis est vide');
    for (final l in lines) {
      if (l.quantity <= 0) throw const BusinessException('Quantité invalide');
      if (l.unitPrice < 0) throw const BusinessException('Le prix ne peut pas être négatif');
    }
    final who = ShopRepository._clean(client);
    final id = await db.transaction<int>((txn) async {
      if (who != null) await _ensureClient(txn, userId, who);
      final number = await _nextNumber(txn, 'quotes', userId);
      final qid = await txn.insert('quotes', {
        'userId': userId,
        'number': number,
        'date': ShopRepository.iso(date),
        'validUntil': validUntil == null ? null : ShopRepository.iso(validUntil),
        'client': who,
        'note': ShopRepository._clean(note),
        'status': QuoteStatus.open.code,
        'createdAt': ShopRepository._now(),
      });
      for (final l in lines) {
        await txn.insert('quote_lines', {
          'quoteId': qid,
          'productId': l.item.product.id,
          'quantity': l.quantity,
          'unitPrice': l.unitPrice,
          'packName': PackMath.isPack(l.packSize) ? l.packName : null,
          'packSize': PackMath.isPack(l.packSize) ? l.packSize : null,
        });
      }
      final total = lines.fold<double>(0, (s, l) => s + l.total);
      await audit(
        userId,
        'Devis',
        'DEV-${number.toString().padLeft(4, '0')} : ${total.round()} FCFA${who == null ? '' : ' ($who)'}',
        executor: txn,
      );
      return qid;
    });
    _changed();
    return (await quote(userId, id))!;
  }

  Future<Quote?> quote(int userId, int quoteId) async {
    final rows = await db.query('quotes', where: 'id = ? AND userId = ?', whereArgs: [quoteId, userId]);
    if (rows.isEmpty) return null;
    final lines = await db.rawQuery('''
      SELECT l.*, p.reference, p.name AS productName, p.unit
      FROM quote_lines l JOIN products p ON p.id = l.productId
      WHERE l.quoteId = ? ORDER BY l.id''', [quoteId]);
    return Quote.fromMap(rows.first, lines.map(QuoteLine.fromMap).toList());
  }

  /// Devis du plus récent au plus ancien (avec leurs lignes).
  Future<List<Quote>> quotes(int userId, {QuoteStatus? status, int limit = 200}) async {
    final rows = await db.query(
      'quotes',
      where: 'userId = ?${status == null ? '' : ' AND status = ?'}',
      whereArgs: [userId, if (status != null) status.code],
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id']).join(',');
    final lines = await db.rawQuery('''
      SELECT l.*, p.reference, p.name AS productName, p.unit
      FROM quote_lines l JOIN products p ON p.id = l.productId
      WHERE l.quoteId IN ($ids) ORDER BY l.id''');
    final byQuote = <int, List<QuoteLine>>{};
    for (final l in lines) {
      (byQuote[l['quoteId'] as int] ??= []).add(QuoteLine.fromMap(l));
    }
    return [for (final r in rows) Quote.fromMap(r, byQuote[r['id'] as int] ?? const [])];
  }

  Future<void> cancelQuote(int userId, int quoteId) async {
    final n = await db.update(
      'quotes',
      {'status': QuoteStatus.cancelled.code},
      where: 'id = ? AND userId = ? AND status = ?',
      whereArgs: [quoteId, userId, QuoteStatus.open.code],
    );
    if (n == 0) throw const BusinessException('Seul un devis en attente peut être annulé');
    await audit(userId, 'Devis', 'Devis #$quoteId annulé');
    _changed();
  }
}
