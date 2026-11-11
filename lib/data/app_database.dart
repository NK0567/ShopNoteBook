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
class AppDatabase {
  static const String fileName = 'shopbook.db';
  static const int version = 3;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? platformDatabaseFactory();
    final dbPath = path ?? join(await f.getDatabasesPath(), fileName);
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
