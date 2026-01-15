import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier, debugPrint;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../database/schema.dart';

class DatabaseProvider with ChangeNotifier {
  static Database? _database;
  static const String _databaseName = 'inara_pos.db';
  static const int _databaseVersion = 1;

  DatabaseProvider();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web. Please use Android or iOS.');
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    // Try to open existing database or create new one
    try {
      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      
      // Add missing columns to existing tables (migration)
      await _addMissingColumns(db);
      
      // Validate that all required tables exist
      try {
        final isValid = await _validateSchema(db);
        if (!isValid) {
          debugPrint('Database: Schema validation failed, resetting database...');
          await db.close();
          await deleteDatabase(path);
          // Recreate database
          return await openDatabase(
            path,
            version: _databaseVersion,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
          );
        }
      } catch (validationError) {
        // If validation itself fails, database is corrupted
        debugPrint('Database: Schema validation error: $validationError');
        debugPrint('Database: Database appears corrupted, resetting...');
        try {
          await db.close();
        } catch (_) {}
        await deleteDatabase(path);
        // Recreate database
        return await openDatabase(
          path,
          version: _databaseVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      }
      
      return db;
    } catch (e) {
      debugPrint('Database: Error opening database: $e');
      debugPrint('Database: Attempting to delete corrupted database and recreate...');
      
      // Try to delete corrupted database and recreate
      try {
        await deleteDatabase(path);
        debugPrint('Database: Deleted corrupted database, recreating...');
        return await openDatabase(
          path,
          version: _databaseVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      } catch (e2) {
        debugPrint('Database: Failed to recreate database: $e2');
        rethrow;
      }
    }
  }

  Future<bool> _validateSchema(Database db) async {
    try {
      // Check if critical tables exist
      final tables = [
        'users',
        'orders',
        'order_items',
        'products',
        'categories',
        'customers',
        'inventory',
        'suppliers',
        'purchases',
        'purchase_items',
        'purchase_payments',
        'expenses',
        'stock_transactions',
        'inventory_ledger',
      ];
      
      for (final table in tables) {
        final result = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table],
        );
        if (result.isEmpty) {
          debugPrint('Database: Table $table is missing');
          return false;
        }
      }
      
      debugPrint('Database: Schema validation passed');
      return true;
    } catch (e) {
      debugPrint('Database: Schema validation error: $e');
      return false;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Use a transaction to ensure all statements execute atomically
    await db.transaction((txn) async {
      // Parse SQL: split by semicolon, filter comments and empty lines
      final lines = createTablesSQL.split('\n');
      final statements = <String>[];
      var currentStatement = StringBuffer();
      
      for (var line in lines) {
        final trimmed = line.trim();
        
        // Skip empty lines and comments
        if (trimmed.isEmpty || trimmed.startsWith('--')) {
          continue;
        }
        
        currentStatement.writeln(line);
        
        // If line ends with semicolon, we have a complete statement
        if (trimmed.endsWith(';')) {
          final stmt = currentStatement.toString().trim();
          if (stmt.isNotEmpty) {
            // Remove trailing semicolon
            final cleanStmt = stmt.replaceAll(RegExp(r';\s*$'), '').trim();
            if (cleanStmt.isNotEmpty) {
              statements.add(cleanStmt);
            }
          }
          currentStatement.clear();
        }
      }
      
      // Handle any remaining statement
      final remaining = currentStatement.toString().trim();
      if (remaining.isNotEmpty && !remaining.endsWith(';')) {
        statements.add(remaining);
      }
      
      // Separate tables from indexes
      final tables = <String>[];
      final indexes = <String>[];
      
      for (final stmt in statements) {
        final upper = stmt.toUpperCase().trim();
        if (upper.startsWith('CREATE TABLE')) {
          tables.add(stmt);
        } else if (upper.startsWith('CREATE INDEX')) {
          indexes.add(stmt);
        }
      }
      
      debugPrint('Database: Will create ${tables.length} tables, then ${indexes.length} indexes');
      
      // Create all tables first
      for (var i = 0; i < tables.length; i++) {
        await txn.execute(tables[i]);
        final nameMatch = RegExp(r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(\w+)', caseSensitive: false).firstMatch(tables[i]);
        debugPrint('Database: ✓ Table ${i + 1}/${tables.length}: ${nameMatch?.group(1) ?? "?"}');
      }
      
      // Then create all indexes
      for (var i = 0; i < indexes.length; i++) {
        await txn.execute(indexes[i]);
        final nameMatch = RegExp(r'CREATE INDEX\s+(?:IF NOT EXISTS\s+)?(\w+)', caseSensitive: false).firstMatch(indexes[i]);
        debugPrint('Database: ✓ Index ${i + 1}/${indexes.length}: ${nameMatch?.group(1) ?? "?"}');
      }
      
      // Initialize default tea café data
      await _initializeDefaultData(txn);
    });
    
    debugPrint('Database: Schema creation completed successfully');
  }
  
  Future<void> _initializeDefaultData(Transaction txn) async {
    try {
      debugPrint('Database: Initializing default tea café data...');
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Check if data already exists
      final existingCategories = await txn.rawQuery('SELECT COUNT(*) as count FROM categories');
      if (existingCategories.first['count'] as int > 0) {
        debugPrint('Database: Default data already exists, skipping initialization');
        return;
      }
      
      // Locked Default Categories (cannot be deleted)
      final categories = [
        {'name': 'Food (Veg/Non Veg)', 'display_order': 1, 'is_active': 1, 'is_locked': 1, 'created_at': now, 'updated_at': now},
        {'name': 'Cigarette', 'display_order': 2, 'is_active': 1, 'is_locked': 1, 'created_at': now, 'updated_at': now},
        {'name': 'Beverages', 'display_order': 3, 'is_active': 1, 'is_locked': 1, 'created_at': now, 'updated_at': now},
      ];
      
      final categoryIds = <int>[];
      for (final cat in categories) {
        final id = await txn.insert('categories', cat);
        categoryIds.add(id);
        debugPrint('Database: Created category: ${cat['name']} (ID: $id)');
      }
      
      // Default Products for Café
      final products = [
        // Food (Veg/Non Veg) Category (index 0)
        {'category_id': categoryIds[0], 'name': 'मोमो (Veg)', 'description': 'Vegetable Momos', 'price': 80.0, 'cost': 30.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[0], 'name': 'मोमो (Non Veg)', 'description': 'Chicken Momos', 'price': 100.0, 'cost': 40.0, 'is_veg': 0, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[0], 'name': 'चाउमिन (Veg)', 'description': 'Vegetable Chowmein', 'price': 70.0, 'cost': 25.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[0], 'name': 'चाउमिन (Non Veg)', 'description': 'Chicken Chowmein', 'price': 90.0, 'cost': 35.0, 'is_veg': 0, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[0], 'name': 'समोसा', 'description': 'Samosa', 'price': 25.0, 'cost': 10.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[0], 'name': 'पकौडा', 'description': 'Pakoda', 'price': 30.0, 'cost': 12.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[0], 'name': 'स्प्रिंग रोल', 'description': 'Spring Roll', 'price': 40.0, 'cost': 15.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        
        // Cigarette Category (index 1)
        {'category_id': categoryIds[1], 'name': 'Marlboro', 'description': 'Marlboro Cigarette', 'price': 150.0, 'cost': 120.0, 'is_veg': 0, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[1], 'name': 'Gold Flake', 'description': 'Gold Flake Cigarette', 'price': 120.0, 'cost': 100.0, 'is_veg': 0, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[1], 'name': '555', 'description': '555 Cigarette', 'price': 130.0, 'cost': 110.0, 'is_veg': 0, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[1], 'name': 'Red & White', 'description': 'Red & White Cigarette', 'price': 110.0, 'cost': 90.0, 'is_veg': 0, 'is_active': 1, 'created_at': now, 'updated_at': now},
        
        // Beverages Category (index 2)
        {'category_id': categoryIds[2], 'name': 'मसाला चिया', 'description': 'Masala Tea', 'price': 30.0, 'cost': 10.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'दूध चिया', 'description': 'Milk Tea', 'price': 25.0, 'cost': 8.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'कालो चिया', 'description': 'Black Tea', 'price': 20.0, 'cost': 5.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'कफी', 'description': 'Coffee', 'price': 40.0, 'cost': 15.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'कोल्ड ड्रिंक', 'description': 'Cold Drink', 'price': 40.0, 'cost': 15.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'जुस', 'description': 'Juice', 'price': 50.0, 'cost': 20.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'ओरेंज जुस', 'description': 'Orange Juice', 'price': 60.0, 'cost': 25.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'एप्पल जुस', 'description': 'Apple Juice', 'price': 60.0, 'cost': 25.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'मिक्स जुस', 'description': 'Mixed Juice', 'price': 70.0, 'cost': 30.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'लस्सी', 'description': 'Lassi', 'price': 55.0, 'cost': 22.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'मंगो लस्सी', 'description': 'Mango Lassi', 'price': 65.0, 'cost': 28.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'सोडा', 'description': 'Soda', 'price': 35.0, 'cost': 12.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
        {'category_id': categoryIds[2], 'name': 'पानी', 'description': 'Water', 'price': 15.0, 'cost': 5.0, 'is_veg': 1, 'is_active': 1, 'created_at': now, 'updated_at': now},
      ];
      
      for (final product in products) {
        final id = await txn.insert('products', product);
        debugPrint('Database: Created product: ${product['name']} (ID: $id)');
        
        // Initialize inventory for each product
        await txn.insert('inventory', {
          'product_id': id,
          'quantity': 100.0,
          'unit': 'pcs',
          'min_stock_level': 10.0,
          'updated_at': now,
        });
      }
      
      // Default Settings
      await txn.insert('settings', {'key': 'cafe_name', 'value': 'चिया गढी', 'updated_at': now});
      await txn.insert('settings', {'key': 'cafe_name_en', 'value': 'Chiya Gadhi', 'updated_at': now});
      await txn.insert('settings', {'key': 'cafe_address', 'value': 'Nepal', 'updated_at': now});
      await txn.insert('settings', {'key': 'tax_percent', 'value': '13', 'updated_at': now}); // VAT percentage (stored as tax_percent for compatibility)
      await txn.insert('settings', {'key': 'currency', 'value': 'NPR', 'updated_at': now});
      await txn.insert('settings', {'key': 'discount_enabled', 'value': '1', 'updated_at': now});
      await txn.insert('settings', {'key': 'default_discount_percent', 'value': '0', 'updated_at': now});
      await txn.insert('settings', {'key': 'max_discount_percent', 'value': '50', 'updated_at': now});
      
      debugPrint('Database: Default tea café data initialized successfully');
    } catch (e) {
      debugPrint('Database: Error initializing default data: $e');
      // Don't throw - allow app to continue even if default data fails
    }
  }

  Future<void> _addMissingColumns(Database db) async {
    try {
      // Check if tables table exists
      final tablesExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tables'",
      );
      
      if (tablesExist.isNotEmpty) {
        // Check if columns exist
        final tableInfo = await db.rawQuery('PRAGMA table_info(tables)');
        final columnNames = tableInfo.map((row) => row['name'] as String).toList();
        
        if (!columnNames.contains('row_position')) {
          await db.execute('ALTER TABLE tables ADD COLUMN row_position INTEGER');
          debugPrint('Database: Added row_position column to tables');
        }
        if (!columnNames.contains('column_position')) {
          await db.execute('ALTER TABLE tables ADD COLUMN column_position INTEGER');
          debugPrint('Database: Added column_position column to tables');
        }
        if (!columnNames.contains('position_label')) {
          await db.execute('ALTER TABLE tables ADD COLUMN position_label TEXT');
          debugPrint('Database: Added position_label column to tables');
        }
        if (!columnNames.contains('notes')) {
          await db.execute('ALTER TABLE tables ADD COLUMN notes TEXT');
          debugPrint('Database: Added notes column to tables');
        }
      }
      
      // Check if categories table exists and add is_locked column
      final categoriesExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'",
      );
      
      if (categoriesExist.isNotEmpty) {
        final categoryInfo = await db.rawQuery('PRAGMA table_info(categories)');
        final categoryColumnNames = categoryInfo.map((row) => row['name'] as String).toList();
        
        if (!categoryColumnNames.contains('is_locked')) {
          await db.execute('ALTER TABLE categories ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0 CHECK(is_locked IN (0, 1))');
          debugPrint('Database: Added is_locked column to categories');
          
          // Mark default categories as locked
          await db.execute("UPDATE categories SET is_locked = 1 WHERE name IN ('Food (Veg/Non Veg)', 'Cigarette', 'Beverages')");
          debugPrint('Database: Marked default categories as locked');
        }
      }
      
      // Check if orders table exists and add credit columns
      final ordersExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='orders'",
      );
      
      if (ordersExist.isNotEmpty) {
        final ordersInfo = await db.rawQuery('PRAGMA table_info(orders)');
        final ordersColumnNames = ordersInfo.map((row) => row['name'] as String).toList();
        
        if (!ordersColumnNames.contains('customer_id')) {
          await db.execute('ALTER TABLE orders ADD COLUMN customer_id INTEGER');
          debugPrint('Database: Added customer_id column to orders');
        }
        if (!ordersColumnNames.contains('credit_amount')) {
          await db.execute('ALTER TABLE orders ADD COLUMN credit_amount REAL NOT NULL DEFAULT 0');
          debugPrint('Database: Added credit_amount column to orders');
        }
        if (!ordersColumnNames.contains('paid_amount')) {
          await db.execute('ALTER TABLE orders ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
          debugPrint('Database: Added paid_amount column to orders');
        }
      }

      // FIXED: Users should support soft-disable (is_active) for multi-user management
      final usersExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
      );
      if (usersExist.isNotEmpty) {
        final usersInfo = await db.rawQuery('PRAGMA table_info(users)');
        final userColumnNames = usersInfo.map((row) => row['name'] as String).toList();
        if (!userColumnNames.contains('is_active')) {
          await db.execute('ALTER TABLE users ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1))');
          debugPrint('Database: Added is_active column to users');
        }
      }

      // FIXED: Ensure product flags exist to separate Purchase items from Menu items
      final productsExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='products'",
      );
      if (productsExist.isNotEmpty) {
        final productInfo = await db.rawQuery('PRAGMA table_info(products)');
        final productColumnNames = productInfo.map((row) => row['name'] as String).toList();

        if (!productColumnNames.contains('is_purchasable')) {
          await db.execute('ALTER TABLE products ADD COLUMN is_purchasable INTEGER NOT NULL DEFAULT 0 CHECK(is_purchasable IN (0, 1))');
          debugPrint('Database: Added is_purchasable column to products');
        }
        if (!productColumnNames.contains('is_sellable')) {
          await db.execute('ALTER TABLE products ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1 CHECK(is_sellable IN (0, 1))');
          debugPrint('Database: Added is_sellable column to products');
        }

        // Existing products are menu items by default.
        // This prevents them from showing up in Purchases unless explicitly marked purchasable.
        await db.execute('UPDATE products SET is_sellable = 1 WHERE is_sellable IS NULL');
        await db.execute('UPDATE products SET is_purchasable = 0 WHERE is_purchasable IS NULL');
      }

      // FIXED: purchase_items must store unit + product_name + notes (used by PurchaseService)
      final purchaseItemsExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_items'",
      );
      if (purchaseItemsExist.isNotEmpty) {
        final info = await db.rawQuery('PRAGMA table_info(purchase_items)');
        final cols = info.map((row) => row['name'] as String).toList();

        if (!cols.contains('product_name')) {
          await db.execute('ALTER TABLE purchase_items ADD COLUMN product_name TEXT');
          debugPrint('Database: Added product_name column to purchase_items');
        }
        if (!cols.contains('unit')) {
          await db.execute("ALTER TABLE purchase_items ADD COLUMN unit TEXT NOT NULL DEFAULT 'pcs'");
          debugPrint('Database: Added unit column to purchase_items');
        }
        if (!cols.contains('notes')) {
          await db.execute('ALTER TABLE purchase_items ADD COLUMN notes TEXT');
          debugPrint('Database: Added notes column to purchase_items');
        }
      }

      // FIXED: Ensure inventory_ledger table exists for ledger-based stock (PurchaseService/OrderService)
      final ledgerExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='inventory_ledger'",
      );
      if (ledgerExist.isEmpty) {
        await db.execute('''
CREATE TABLE IF NOT EXISTS inventory_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL,
  product_name TEXT,
  unit TEXT NOT NULL DEFAULT 'pcs',
  quantity_in REAL NOT NULL DEFAULT 0,
  quantity_out REAL NOT NULL DEFAULT 0,
  unit_price REAL DEFAULT 0,
  transaction_type TEXT,
  reference_type TEXT,
  reference_id INTEGER,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (product_id) REFERENCES products(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);
''');
        debugPrint('Database: Created inventory_ledger table');
      }

      // FIXED: Ensure suppliers table exists (used by SuppliersScreen/SupplierService)
      final suppliersExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='suppliers'",
      );
      if (suppliersExist.isEmpty) {
        await db.execute('''
CREATE TABLE IF NOT EXISTS suppliers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  notes TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
        debugPrint('Database: Created suppliers table');
      }

      // FIXED: purchases should store vendor bill/invoice number (bill_number)
      final purchasesExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchases'",
      );
      if (purchasesExist.isNotEmpty) {
        final info = await db.rawQuery('PRAGMA table_info(purchases)');
        final cols = info.map((row) => row['name'] as String).toList();

        if (!cols.contains('bill_number')) {
          await db.execute('ALTER TABLE purchases ADD COLUMN bill_number TEXT');
          debugPrint('Database: Added bill_number column to purchases');
        }

        // FIXED: Payment tracking fields (used by PurchasesScreen + PurchaseService)
        if (!cols.contains('supplier_id')) {
          await db.execute('ALTER TABLE purchases ADD COLUMN supplier_id INTEGER');
          debugPrint('Database: Added supplier_id column to purchases');
        }
        if (!cols.contains('discount_amount')) {
          await db.execute('ALTER TABLE purchases ADD COLUMN discount_amount REAL NOT NULL DEFAULT 0');
          debugPrint('Database: Added discount_amount column to purchases');
        }
        if (!cols.contains('tax_amount')) {
          await db.execute('ALTER TABLE purchases ADD COLUMN tax_amount REAL NOT NULL DEFAULT 0');
          debugPrint('Database: Added tax_amount column to purchases');
        }
        if (!cols.contains('paid_amount')) {
          await db.execute('ALTER TABLE purchases ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
          debugPrint('Database: Added paid_amount column to purchases');
        }
        if (!cols.contains('outstanding_amount')) {
          await db.execute('ALTER TABLE purchases ADD COLUMN outstanding_amount REAL NOT NULL DEFAULT 0');
          debugPrint('Database: Added outstanding_amount column to purchases');
        }
        if (!cols.contains('payment_status')) {
          await db.execute("ALTER TABLE purchases ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'unpaid'");
          debugPrint('Database: Added payment_status column to purchases');
        }
        if (!cols.contains('status')) {
          await db.execute("ALTER TABLE purchases ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'");
          debugPrint('Database: Added status column to purchases');
        }
      }

      // FIXED: Ensure purchase_payments table exists (like customer credit_transactions payments)
      final purchasePaymentsExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_payments'",
      );
      if (purchasePaymentsExist.isEmpty) {
        await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  payment_method TEXT,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id)
);
''');
        debugPrint('Database: Created purchase_payments table');
      }

      // FIXED: Ensure expenses table exists (in-house expenses)
      final expensesExist = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='expenses'",
      );
      if (expensesExist.isEmpty) {
        await db.execute('''
CREATE TABLE IF NOT EXISTS expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  expense_number TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  category TEXT,
  amount REAL NOT NULL,
  payment_method TEXT CHECK(payment_method IN ('cash', 'card', 'bank_transfer', 'other')),
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (created_by) REFERENCES users(id)
);
''');
        debugPrint('Database: Created expenses table');
      }
    } catch (e) {
      debugPrint('Database: Error adding missing columns: $e');
      // Continue - columns might already exist or table might not exist yet
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('Database: Upgrading from version $oldVersion to $newVersion');
    await _addMissingColumns(db);
  }

  Future<void> init() async {
    if (kIsWeb) {
      debugPrint('Database initialization skipped on web platform');
      return;
    }
    
    try {
      debugPrint('Database: Initializing database...');
      await database; // This will validate and reset if needed
      debugPrint('Database: Initialization successful');
    } catch (e) {
      debugPrint('Database: Initialization failed: $e');
      // Try to reset and recreate
      try {
        debugPrint('Database: Attempting automatic reset...');
        await resetDatabase();
        debugPrint('Database: Automatic reset successful');
      } catch (e2) {
        debugPrint('Database: Automatic reset also failed: $e2');
        rethrow;
      }
    }
  }

  // Generic query methods
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return await db.insert(table, values);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<T?> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  // Reset database (delete and recreate) - use with caution!
  Future<void> resetDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web.');
    }
    
    debugPrint('Database: Starting database reset...');
    
    try {
      // Close existing connection first
      if (_database != null) {
        try {
          await _database!.close();
          debugPrint('Database: Closed existing connection');
        } catch (e) {
          debugPrint('Database: Error closing connection (may already be closed): $e');
        }
        _database = null;
      }
      
      // Wait a bit to ensure connection is fully closed
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Delete database file
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _databaseName);
      
      try {
        await deleteDatabase(path);
        debugPrint('Database: Deleted database file at $path');
      } catch (e) {
        debugPrint('Database: Error deleting database file: $e');
        // Try to delete again after a short delay
        await Future.delayed(const Duration(milliseconds: 200));
        try {
          await deleteDatabase(path);
          debugPrint('Database: Successfully deleted database file on retry');
        } catch (e2) {
          debugPrint('Database: Failed to delete database file after retry: $e2');
          throw Exception('Could not delete database file: $e2');
        }
      }
      
      // Wait a bit before recreating
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Recreate database
      debugPrint('Database: Recreating database...');
      _database = await _initDatabase();
      debugPrint('Database: Database reset complete successfully');
    } catch (e, stackTrace) {
      debugPrint('Database: Reset failed with error: $e');
      debugPrint('Database: Stack trace: $stackTrace');
      _database = null; // Ensure it's null on failure
      rethrow;
    }
  }

  // Close database (usually not needed, but available for cleanup)
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
