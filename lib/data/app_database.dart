import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'db_factory.dart';

/// Ouverture et schéma de la base SQLite locale.
///
/// v1 : schéma initial (users / products / sales / purchases).
/// v2 : refonte basée sur les classeurs Excel — catalogue avec référence
///      unique, catégories, journal unique des mouvements (entrées/sorties),
///      inventaire calculé (CUMP), journal d'audit, verrouillage de compte.
/// v3 : tickets de caisse multi-articles, encaissements et ventes à crédit,
///      pertes / écarts d'inventaire, code de secours du mot de passe.
/// v4 : boutique paramétrable (tarifs, conditionnements, clients, devis, factures).
class AppDatabase {
  static const String fileName = 'shopbook.db';
  static const int version = 4;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? platformDatabaseFactory();
    final dbPath = path ?? join(await platformDatabaseDir(f), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: _onUpgrade,
      ),
    );
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        passwordHash TEXT NOT NULL,
        businessName TEXT NOT NULL,
        defaultAlertThreshold INTEGER NOT NULL DEFAULT 10 CHECK (defaultAlertThreshold >= 0),
        warningColor INTEGER NOT NULL DEFAULT 4294940672,
        criticalColor INTEGER NOT NULL DEFAULT 4294198070,
        autoLockMinutes INTEGER NOT NULL DEFAULT 5 CHECK (autoLockMinutes >= 0),
        failedAttempts INTEGER NOT NULL DEFAULT 0,
        lockedUntil TEXT,
        recoveryHash TEXT,
        createdAt TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL COLLATE NOCASE,
        UNIQUE (userId, name)
      )''');
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        reference TEXT NOT NULL COLLATE NOCASE,
        name TEXT NOT NULL,
        categoryId INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        unit TEXT NOT NULL DEFAULT 'unité',
        alertThreshold INTEGER NOT NULL CHECK (alertThreshold >= 0),
        initialStock INTEGER NOT NULL DEFAULT 0 CHECK (initialStock >= 0),
        initialUnitCost REAL NOT NULL DEFAULT 0 CHECK (initialUnitCost >= 0),
        sellingPrice REAL NOT NULL DEFAULT 0 CHECK (sellingPrice >= 0),
        archived INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE (userId, reference)
      )''');
    await _createTicketTables(db);
    await _createMovementsTable(db, 'movements');
    await _createMovementIndexes(db);
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )''');
    await _addV4(db);
  }

  /// Tickets de caisse (une vente = un ticket de une ou plusieurs lignes)
  /// et encaissements (paiement comptant, acomptes et remboursements de crédit).
  static Future<void> _createTicketTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE tickets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        number INTEGER NOT NULL,
        date TEXT NOT NULL,
        client TEXT,
        note TEXT,
        createdAt TEXT NOT NULL,
        UNIQUE (userId, number)
      )''');
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        ticketId INTEGER NOT NULL REFERENCES tickets(id),
        amount REAL NOT NULL CHECK (amount <> 0), -- négatif = remboursement au client
        date TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'Espèces',
        note TEXT,
        cancelled INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_tickets_client ON tickets(userId, client)');
    await db.execute('CREATE INDEX idx_payments_ticket ON payments(ticketId)');
  }

  /// IN = entrée (achat), OUT = vente, LOSS = perte (casse, vol, périmé, écart d'inventaire).
  static Future<void> _createMovementsTable(DatabaseExecutor db, String name) => db.execute('''
      CREATE TABLE $name (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        productId INTEGER NOT NULL REFERENCES products(id),
        type TEXT NOT NULL CHECK (type IN ('IN', 'OUT', 'LOSS')),
        number INTEGER NOT NULL,
        date TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        unitPrice REAL NOT NULL CHECK (unitPrice >= 0),
        unitCost REAL NOT NULL DEFAULT 0 CHECK (unitCost >= 0),
        partner TEXT,
        note TEXT,
        ticketId INTEGER REFERENCES tickets(id),
        cancelled INTEGER NOT NULL DEFAULT 0,
        cancelReason TEXT,
        cancelledAt TEXT,
        createdAt TEXT NOT NULL,
        UNIQUE (userId, type, number)
      )''');

  static Future<void> _createMovementIndexes(DatabaseExecutor db) async {
    await db.execute('CREATE INDEX idx_movements_user_date ON movements(userId, date)');
    await db.execute('CREATE INDEX idx_movements_product ON movements(productId)');
    await db.execute('CREATE INDEX idx_movements_ticket ON movements(ticketId)');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // La migration v1 crée directement le schéma le plus récent.
    if (oldVersion < 2) {
      await _migrateV1toV2(db);
      return;
    }
    if (oldVersion < 3) await _migrateV2toV3(db);
    if (oldVersion < 4) await _addV4(db);
  }

  /// v4 : boutique paramétrable (détaillant, grossiste ou les deux).
  /// - profil de la boutique (coordonnées, NIU, RCCM, TVA) pour les factures ;
  /// - grilles de tarifs libres (Détail, Demi-gros, Gros…) avec paliers de quantité ;
  /// - conditionnements (carton de 24, sac de 50 kg…) et codes-barres ;
  /// - fiches clients (tarif attitré, plafond de crédit) ;
  /// - devis / factures pro forma et numérotation des factures.
  static Future<void> _addV4(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE shop_profile (
        userId INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        shopType TEXT NOT NULL DEFAULT 'retail' CHECK (shopType IN ('retail', 'wholesale', 'hybrid')),
        activity TEXT,
        address TEXT,
        city TEXT,
        phone TEXT,
        niu TEXT,
        rccm TEXT,
        invoiceFooter TEXT,
        vatEnabled INTEGER NOT NULL DEFAULT 0,
        vatRate REAL NOT NULL DEFAULT 19.25 CHECK (vatRate >= 0 AND vatRate < 100),
        receiptWidth INTEGER NOT NULL DEFAULT 80 CHECK (receiptWidth IN (58, 80))
      )''');
    await db.execute('''
      CREATE TABLE price_levels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL COLLATE NOCASE,
        minQty INTEGER NOT NULL DEFAULT 0 CHECK (minQty >= 0),
        position INTEGER NOT NULL DEFAULT 0,
        UNIQUE (userId, name)
      )''');
    await db.execute('''
      CREATE TABLE product_prices (
        productId INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        levelId INTEGER NOT NULL REFERENCES price_levels(id) ON DELETE CASCADE,
        price REAL NOT NULL CHECK (price >= 0),
        -- Palier propre au produit : ce prix s'applique d'office dès minQty unités.
        minQty INTEGER NOT NULL DEFAULT 0 CHECK (minQty >= 0),
        PRIMARY KEY (productId, levelId)
      )''');
    await db.execute('''
      CREATE TABLE product_packs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        productId INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity > 1),
        price REAL NOT NULL DEFAULT 0 CHECK (price >= 0), -- 0 = prix unitaire x quantité
        barcode TEXT
      )''');
    await db.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
    await db.execute('CREATE INDEX idx_products_barcode ON products(userId, barcode)');
    await db.execute('''
      CREATE TABLE clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL COLLATE NOCASE,
        phone TEXT,
        address TEXT,
        niu TEXT,
        priceLevelId INTEGER REFERENCES price_levels(id) ON DELETE SET NULL,
        creditLimit REAL NOT NULL DEFAULT 0 CHECK (creditLimit >= 0), -- 0 = sans plafond
        note TEXT,
        createdAt TEXT NOT NULL,
        UNIQUE (userId, name)
      )''');
    // Les clients déjà cités sur des tickets deviennent des fiches clients.
    await db.execute('''
      INSERT OR IGNORE INTO clients (userId, name, createdAt)
      SELECT userId, trim(client), MIN(createdAt) FROM tickets
      WHERE trim(COALESCE(client, '')) <> '' GROUP BY userId, trim(client) COLLATE NOCASE''');
    await db.execute('ALTER TABLE tickets ADD COLUMN priceLevelId INTEGER');
    await db.execute('ALTER TABLE tickets ADD COLUMN invoiceYear INTEGER');
    await db.execute('ALTER TABLE tickets ADD COLUMN invoiceNumber INTEGER');
    await db.execute('ALTER TABLE tickets ADD COLUMN invoiceDate TEXT');
    await db.execute(
      'CREATE UNIQUE INDEX idx_tickets_invoice ON tickets(userId, invoiceYear, invoiceNumber) '
      'WHERE invoiceNumber IS NOT NULL',
    );
    await db.execute('ALTER TABLE movements ADD COLUMN packName TEXT');
    await db.execute('ALTER TABLE movements ADD COLUMN packSize INTEGER');
    await db.execute('''
      CREATE TABLE quotes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        number INTEGER NOT NULL,
        date TEXT NOT NULL,
        validUntil TEXT,
        client TEXT,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'converted', 'cancelled')),
        ticketId INTEGER REFERENCES tickets(id),
        createdAt TEXT NOT NULL,
        UNIQUE (userId, number)
      )''');
    await db.execute('''
      CREATE TABLE quote_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quoteId INTEGER NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
        productId INTEGER NOT NULL REFERENCES products(id),
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        unitPrice REAL NOT NULL CHECK (unitPrice >= 0),
        packName TEXT,
        packSize INTEGER
      )''');
  }

  /// v3 : tickets de caisse, encaissements / crédits, pertes, code de secours.
  /// SQLite ne sait pas modifier une contrainte CHECK : la table des mouvements
  /// est reconstruite à l'identique avec la nouvelle colonne ticketId.
  /// Les ventes existantes restent sans ticket et sont considérées comme payées.
  static Future<void> _migrateV2toV3(Database db) async {
    await db.execute('ALTER TABLE users ADD COLUMN recoveryHash TEXT');
    await _createTicketTables(db);
    await _createMovementsTable(db, 'movements_v3');
    await db.execute('''
      INSERT INTO movements_v3 (id, userId, productId, type, number, date, quantity, unitPrice,
          unitCost, partner, note, cancelled, cancelReason, cancelledAt, createdAt)
      SELECT id, userId, productId, type, number, date, quantity, unitPrice,
          unitCost, partner, note, cancelled, cancelReason, cancelledAt, createdAt
      FROM movements''');
    await db.execute('DROP TABLE movements');
    await db.execute('ALTER TABLE movements_v3 RENAME TO movements');
    await _createMovementIndexes(db);
  }

  /// Reprend les comptes et données de la v1 dans le nouveau schéma.
  /// Les mots de passe SHA256 non salés sont convertis en PBKDF2 à la
  /// prochaine connexion réussie.
  static Future<void> _migrateV1toV2(Database db) async {
    // sqflite exécute déjà onUpgrade dans une transaction.
    final txn = db;
    {
      for (final t in ['users', 'products', 'sales', 'purchases']) {
        await txn.execute('ALTER TABLE $t RENAME TO ${t}_v1');
      }
      await _createSchema(txn);

      await txn.execute('''
        INSERT INTO users (id, name, email, passwordHash, businessName,
                           defaultAlertThreshold, createdAt)
        SELECT id, name, lower(trim(email)), passwordHash, businessName,
               COALESCE(warningStockThreshold, 10), createdAt
        FROM users_v1''');

      await txn.execute('''
        INSERT OR IGNORE INTO categories (userId, name)
        SELECT DISTINCT userId, trim(category) FROM products_v1
        WHERE trim(COALESCE(category, '')) <> ''
      ''');

      // Le stock initial est reconstitué pour que :
      // initial + entrées - sorties = quantité connue en v1.
      await txn.execute('''
        INSERT INTO products (id, userId, reference, name, categoryId, unit,
            alertThreshold, initialStock, initialUnitCost, sellingPrice,
            archived, createdAt, updatedAt)
        SELECT p.id, p.userId, 'P' || p.id, p.name,
          (SELECT c.id FROM categories c WHERE c.userId = p.userId AND c.name = trim(p.category)),
          COALESCE(NULLIF(trim(p.unit), ''), 'unité'),
          MAX(p.lowStockThreshold, 0),
          MAX(0, p.quantity
                 - COALESCE((SELECT SUM(quantity) FROM purchases_v1 x WHERE x.productId = p.id), 0)
                 + COALESCE((SELECT SUM(quantity) FROM sales_v1 x WHERE x.productId = p.id), 0)),
          MAX(p.costPrice, 0), MAX(p.sellingPrice, 0), 0, p.createdAt, p.updatedAt
        FROM products_v1 p''');

      await txn.execute('''
        INSERT INTO movements (userId, productId, type, number, date, quantity,
            unitPrice, unitCost, partner, note, createdAt)
        SELECT u.userId, u.productId, 'IN',
          (SELECT COUNT(*) FROM purchases_v1 x WHERE x.userId = u.userId AND x.id <= u.id),
          u.purchaseDate, u.quantity, u.unitCostPrice, u.unitCostPrice, u.supplier,
          TRIM(COALESCE('Facture ' || u.invoiceNumber, '') || ' ' || COALESCE(u.notes, '')),
          u.purchaseDate
        FROM purchases_v1 u
        WHERE u.quantity > 0 AND u.productId IN (SELECT id FROM products)''');

      await txn.execute('''
        INSERT INTO movements (userId, productId, type, number, date, quantity,
            unitPrice, unitCost, note, createdAt)
        SELECT s.userId, s.productId, 'OUT',
          (SELECT COUNT(*) FROM sales_v1 x WHERE x.userId = s.userId AND x.id <= s.id),
          s.saleDate, s.quantity, s.unitPrice,
          MAX(0, s.unitPrice - s.profit / s.quantity), s.notes, s.saleDate
        FROM sales_v1 s
        WHERE s.quantity > 0 AND s.productId IN (SELECT id FROM products)''');

      for (final t in ['sales', 'purchases', 'products', 'users']) {
        await txn.execute('DROP TABLE ${t}_v1');
      }
    }
  }
}
