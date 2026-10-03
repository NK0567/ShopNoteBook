import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/purchase.dart';

/// Service de gestion de la base de données SQLite
/// Gère toutes les opérations CRUD (Create, Read, Update, Delete) pour les données
class DatabaseService {
  // Instance unique de la base de données (pattern Singleton)
  static Database? _database;
  
  // Nom de la base de données
  static const String _dbName = 'shopbook.db';
  
  // Version de la base de données (augmenter en cas de migration)
  static const int _dbVersion = 1;
  
  // Noms des tables dans la base de données
  static const String _usersTable = 'users';
  static const String _productsTable = 'products';
  static const String _salesTable = 'sales';
  static const String _purchasesTable = 'purchases';

  // Fallback simple en mémoire pour exécuter l'app sur le Web (sqflite non supporté)
  // Structure: id -> map des champs
  static final Map<int, Map<String, dynamic>> _inMemoryUsers = {};
  static int _inMemoryUserAutoId = 1;

  /// Getter pour obtenir l'instance de la base de données
  /// Initialise la BDD la première fois qu'elle est accédée
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialise la base de données et crée les tables
  /// Cette méthode est appelée une seule fois au premier lancement
  static Future<Database> _initDatabase() async {
    // Obtient le chemin du répertoire des documents de l'application
    final dbPath = await getDatabasesPath();
    
    // Combine le chemin avec le nom de la BDD
    final path = join(dbPath, _dbName);
    
    // Ouvre ou crée la base de données
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  /// Crée toutes les tables de la base de données lors de la première utilisation
  static Future<void> _onCreate(Database db, int version) async {
    // Crée la table des utilisateurs
    await db.execute('''
      CREATE TABLE $_usersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        passwordHash TEXT NOT NULL,
        businessName TEXT NOT NULL,
        criticalStockThreshold INTEGER DEFAULT 5,
        warningStockThreshold INTEGER DEFAULT 10,
        warningColor TEXT DEFAULT '#FF9800',
        criticalColor TEXT DEFAULT '#F44336',
        createdAt TEXT NOT NULL
      )
    ''');

    // Crée la table des produits
    await db.execute('''
      CREATE TABLE $_productsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        costPrice REAL NOT NULL,
        sellingPrice REAL NOT NULL,
        quantity INTEGER NOT NULL,
        totalSoldQuantity INTEGER DEFAULT 0,
        lowStockThreshold INTEGER NOT NULL,
        criticalStockThreshold INTEGER NOT NULL,
        category TEXT NOT NULL,
        unit TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (userId) REFERENCES $_usersTable(id)
      )
    ''');

    // Crée la table des ventes
    await db.execute('''
      CREATE TABLE $_salesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unitPrice REAL NOT NULL,
        totalAmount REAL NOT NULL,
        profit REAL NOT NULL,
        saleDate TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (userId) REFERENCES $_usersTable(id),
        FOREIGN KEY (productId) REFERENCES $_productsTable(id)
      )
    ''');

    // Crée la table des réapprovisionnements
    await db.execute('''
      CREATE TABLE $_purchasesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unitCostPrice REAL NOT NULL,
        totalCost REAL NOT NULL,
        supplier TEXT NOT NULL,
        invoiceNumber TEXT,
        purchaseDate TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (userId) REFERENCES $_usersTable(id),
        FOREIGN KEY (productId) REFERENCES $_productsTable(id)
      )
    ''');
  }

  // ========== OPÉRATIONS UTILISATEUR ==========

  /// Enregistre un nouvel utilisateur dans la base de données
  static Future<int> createUser(User user) async {
    // Si on est sur le web, sqflite n'est pas disponible: utilise un fallback en mémoire
    if (kIsWeb) {
      // stockage en mémoire minimal pour les utilisateurs (développement web)
      _inMemoryUsers[_inMemoryUserAutoId] = user.toMap()..['id'] = _inMemoryUserAutoId;
      return _inMemoryUserAutoId++;
    }

    final db = await database;
    return await db.insert(
      _usersTable,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère un utilisateur par son email (pour l'authentification)
  static Future<User?> getUserByEmail(String email) async {
    if (kIsWeb) {
      // Rechercher dans le fallback mémoire
      final entry = _inMemoryUsers.entries
          .firstWhere((e) => (e.value['email'] as String?) == email, orElse: () => MapEntry(-1, {}));
      if (entry.key == -1) return null;
      return User.fromMap(entry.value);
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _usersTable,
      where: 'email = ?',
      whereArgs: [email],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  /// Récupère un utilisateur par son ID
  static Future<User?> getUserById(int id) async {
    if (kIsWeb) {
      final map = _inMemoryUsers[id];
      if (map == null) return null;
      return User.fromMap(map);
    }

    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _usersTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  /// Met à jour les paramètres de l'utilisateur
  static Future<int> updateUser(User user) async {
    if (kIsWeb) {
      if (user.id == null) return 0;
      _inMemoryUsers[user.id!] = user.toMap();
      return 1;
    }

    final db = await database;
    return await db.update(
      _usersTable,
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  // ========== OPÉRATIONS PRODUIT ==========

  /// Crée un nouveau produit dans le catalogue
  static Future<int> createProduct(Product product) async {
    final db = await database;
    return await db.insert(
      _productsTable,
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère tous les produits d'un utilisateur
  static Future<List<Product>> getProductsByUserId(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productsTable,
      where: 'userId = ?',
      whereArgs: [userId],
    );

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Recherche un produit par son nom pour un utilisateur spécifique
  static Future<Product?> getProductByName(int userId, String name) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productsTable,
      where: 'userId = ? AND name = ?',
      whereArgs: [userId, name],
    );

    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    }
    return null;
  }

  /// Récupère les 3 produits les plus demandés (plus vendus)
  static Future<List<Product>> getTopProducts(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productsTable,
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'totalSoldQuantity DESC',
      limit: 3,
    );

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Récupère les produits avec stock faible ou critique pour un utilisateur
  static Future<List<Product>> getLowStockProducts(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productsTable,
      where: 'userId = ? AND (quantity <= lowStockThreshold OR quantity <= criticalStockThreshold)',
      whereArgs: [userId],
      orderBy: 'quantity ASC',
    );

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Récupère les produits avec stock critique uniquement (alerte rouge)
  static Future<List<Product>> getCriticalStockProducts(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productsTable,
      where: 'userId = ? AND quantity <= criticalStockThreshold',
      whereArgs: [userId],
      orderBy: 'quantity ASC',
    );

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Récupère les produits avec stock faible (alerte orange)
  static Future<List<Product>> getWarningStockProducts(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _productsTable,
      where: 'userId = ? AND quantity > criticalStockThreshold AND quantity <= lowStockThreshold',
      whereArgs: [userId],
      orderBy: 'quantity ASC',
    );

    return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
  }

  /// Met à jour un produit existant
  static Future<int> updateProduct(Product product) async {
    final db = await database;
    return await db.update(
      _productsTable,
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  // ========== OPÉRATIONS VENTE ==========

  /// Enregistre une nouvelle vente dans l'historique
  static Future<int> createSale(Sale sale) async {
    final db = await database;
    return await db.insert(
      _salesTable,
      sale.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère toutes les ventes d'un utilisateur
  static Future<List<Sale>> getSalesByUserId(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _salesTable,
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'saleDate DESC',
    );

    return List.generate(maps.length, (i) => Sale.fromMap(maps[i]));
  }

  /// Récupère les ventes d'une date spécifique
  static Future<List<Sale>> getSalesByDate(int userId, String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _salesTable,
      where: 'userId = ? AND DATE(saleDate) = ?',
      whereArgs: [userId, date],
      orderBy: 'saleDate DESC',
    );

    return List.generate(maps.length, (i) => Sale.fromMap(maps[i]));
  }

  /// Calcule le bénéfice total pour une période donnée
  static Future<double> getTotalProfitForPeriod(
    int userId,
    String startDate,
    String endDate,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT SUM(profit) as totalProfit FROM $_salesTable WHERE userId = ? AND saleDate >= ? AND saleDate <= ?',
      [userId, startDate, endDate],
    );

    if (result.isNotEmpty && result.first['totalProfit'] != null) {
      return (result.first['totalProfit'] as num).toDouble();
    }
    return 0.0;
  }

  // ========== OPÉRATIONS RÉAPPROVISIONNEMENT ==========

  /// Enregistre un nouvel achat/réapprovisionnement
  static Future<int> createPurchase(Purchase purchase) async {
    final db = await database;
    return await db.insert(
      _purchasesTable,
      purchase.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère tous les réapprovisionnements d'un utilisateur
  static Future<List<Purchase>> getPurchasesByUserId(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _purchasesTable,
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'purchaseDate DESC',
    );

    return List.generate(maps.length, (i) => Purchase.fromMap(maps[i]));
  }

  /// Ferme la base de données (appelé lors de la fermeture de l'application)
  static Future<void> close() async {
    final db = await database;
    db.close();
  }
}
