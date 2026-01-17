import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/database_provider.dart';

class InventoryService {
  DatabaseProvider? _db;

  DatabaseProvider _getDb(BuildContext? context) {
    if (context != null) {
      // Use Provider if context is available
      return Provider.of<DatabaseProvider>(context, listen: false);
    }
    // Fallback to singleton instance
    if (_db == null) {
      _db = DatabaseProvider();
    }
    return _db!;
  }

  /// Increase stock from purchase (transactional)
  Future<void> increaseStockFromPurchase({
    required int productId,
    required double quantity,
    required double unitPrice,
    required int purchaseId,
    int? createdBy,
    String? notes,
    BuildContext? context,
  }) async {
    final dbProvider = _getDb(context);
    final db = await dbProvider.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Get or create inventory record
      final inventory = await txn.query(
        'inventory',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      double newQuantity;
      if (inventory.isEmpty) {
        // Create new inventory record
        newQuantity = quantity;
        await txn.insert('inventory', {
          'product_id': productId,
          'quantity': newQuantity,
          'unit': 'pcs', // Default unit
          'min_stock_level': 0,
          'updated_at': now,
        });
      } else {
        // Update existing inventory
        final currentQty = (inventory.first['quantity'] as num).toDouble();
        newQuantity = currentQty + quantity;
        await txn.update(
          'inventory',
          {
            'quantity': newQuantity,
            'updated_at': now,
          },
          where: 'product_id = ?',
          whereArgs: [productId],
        );
      }

      // Update product cost (average cost method)
      await _updateProductCost(txn, productId, unitPrice, quantity);

      // Create stock transaction
      await txn.insert('stock_transactions', {
        'product_id': productId,
        'transaction_type': 'in',
        'quantity': quantity,
        'unit_price': unitPrice,
        'reference_type': 'purchase',
        'reference_id': purchaseId,
        'notes': notes,
        'created_by': createdBy,
        'created_at': now,
        'synced': 0,
      });
    });
  }

  /// Decrease stock from sale (transactional, prevents negative stock)
  Future<bool> decreaseStockFromSale({
    required int productId,
    required double quantity,
    required double unitPrice,
    required int orderId,
    int? createdBy,
    BuildContext? context,
  }) async {
    final dbProvider = _getDb(context);
    final db = await dbProvider.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    bool success = false;
    await db.transaction((txn) async {
      // Get inventory
      final inventory = await txn.query(
        'inventory',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      if (inventory.isEmpty) {
        throw Exception('Product has no inventory record');
      }

      final currentQty = (inventory.first['quantity'] as num).toDouble();
      final newQty = currentQty - quantity;

      // Prevent negative stock
      if (newQty < 0) {
        throw Exception(
            'Insufficient stock. Available: $currentQty, Required: $quantity');
      }

      // Update inventory
      await txn.update(
        'inventory',
        {
          'quantity': newQty,
          'updated_at': now,
        },
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      // Create stock transaction
      await txn.insert('stock_transactions', {
        'product_id': productId,
        'transaction_type': 'out',
        'quantity': -quantity,
        'unit_price': unitPrice,
        'reference_type': 'sale',
        'reference_id': orderId,
        'created_by': createdBy,
        'created_at': now,
        'synced': 0,
      });

      success = true;
    });

    return success;
  }

  /// Update product cost using weighted average method
  Future<void> _updateProductCost(
    dynamic txn,
    int productId,
    double newCost,
    double newQuantity,
  ) async {
    // Get current product
    final products = await txn.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    );

    if (products.isEmpty) return;

    final product = products.first;
    final currentCost = (product['cost'] as num? ?? 0).toDouble();
    final currentQty = await _getCurrentInventoryQuantity(txn, productId);

    // Calculate weighted average cost
    double newAverageCost;
    if (currentQty == 0) {
      newAverageCost = newCost;
    } else {
      final totalCurrentValue = currentCost * currentQty;
      final totalNewValue = newCost * newQuantity;
      final totalQuantity = currentQty + newQuantity;
      newAverageCost = (totalCurrentValue + totalNewValue) / totalQuantity;
    }

    // Update product cost
    await txn.update(
      'products',
      {
        'cost': newAverageCost,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  /// Get current inventory quantity
  Future<double> _getCurrentInventoryQuantity(
      dynamic txn, int productId) async {
    final inventory = await txn.query(
      'inventory',
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    if (inventory.isEmpty) return 0.0;
    return (inventory.first['quantity'] as num).toDouble();
  }

  /// Check stock availability before sale
  Future<bool> checkStockAvailability({
    required int productId,
    required double quantity,
    BuildContext? context,
  }) async {
    final dbProvider = _getDb(context);
    final inventory = await dbProvider.query(
      'inventory',
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    if (inventory.isEmpty) return false;
    final availableQty = (inventory.first['quantity'] as num).toDouble();
    return availableQty >= quantity;
  }

  /// Get available stock quantity
  Future<double> getAvailableStock(int productId,
      {BuildContext? context}) async {
    final dbProvider = _getDb(context);
    final inventory = await dbProvider.query(
      'inventory',
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    if (inventory.isEmpty) return 0.0;
    return (inventory.first['quantity'] as num).toDouble();
  }

  /// Get low stock items
  Future<List<Map<String, dynamic>>> getLowStockItems(
      {BuildContext? context}) async {
    final dbProvider = _getDb(context);
    return await dbProvider.query('''
      SELECT 
        i.*,
        p.name as product_name,
        p.price as selling_price,
        p.cost as purchase_price,
        c.name as category_name
      FROM inventory i
      JOIN products p ON i.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE i.quantity <= i.min_stock_level
      ORDER BY (i.quantity / NULLIF(i.min_stock_level, 0)) ASC, p.name ASC
    ''');
  }

  /// Manual stock adjustment (transactional)
  Future<void> adjustStock({
    required int productId,
    required double newQuantity,
    required String transactionType,
    String? notes,
    int? createdBy,
    BuildContext? context,
  }) async {
    final dbProvider = _getDb(context);
    final db = await dbProvider.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Get current inventory
      final inventory = await txn.query(
        'inventory',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      if (inventory.isEmpty) {
        throw Exception('Product has no inventory record');
      }

      final currentQty = (inventory.first['quantity'] as num).toDouble();
      final difference = newQuantity - currentQty;

      // Prevent negative stock
      if (newQuantity < 0) {
        throw Exception('Stock cannot be negative');
      }

      // Update inventory
      await txn.update(
        'inventory',
        {
          'quantity': newQuantity,
          'updated_at': now,
        },
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      // Create stock transaction if there's a difference
      if (difference != 0) {
        await txn.insert('stock_transactions', {
          'product_id': productId,
          'transaction_type': transactionType,
          'quantity': difference,
          'reference_type': 'adjustment',
          'notes': notes,
          'created_by': createdBy,
          'created_at': now,
          'synced': 0,
        });
      }
    });
  }

  /// Get stock movement history
  Future<List<Map<String, dynamic>>> getStockMovementHistory({
    int? productId,
    String? transactionType,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    BuildContext? context,
  }) async {
    final dbProvider = _getDb(context);

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (productId != null) {
      whereClause += ' AND st.product_id = ?';
      whereArgs.add(productId);
    }

    if (transactionType != null) {
      whereClause += ' AND st.transaction_type = ?';
      whereArgs.add(transactionType);
    }

    if (startDate != null) {
      whereClause += ' AND st.created_at >= ?';
      whereArgs.add(startDate.millisecondsSinceEpoch);
    }

    if (endDate != null) {
      whereClause += ' AND st.created_at <= ?';
      whereArgs.add(endDate.millisecondsSinceEpoch);
    }

    return await dbProvider.query('''
      SELECT 
        st.*,
        p.name as product_name,
        p.price as selling_price,
        p.cost as purchase_price
      FROM stock_transactions st
      JOIN products p ON st.product_id = p.id
      WHERE $whereClause
      ORDER BY st.created_at DESC
      LIMIT ?
    ''', whereArgs: [...whereArgs, limit]);
  }

  /// Get inventory report with profit margins
  Future<List<Map<String, dynamic>>> getInventoryReport(
      {BuildContext? context}) async {
    final dbProvider = _getDb(context);
    return await dbProvider.query('''
      SELECT 
        i.*,
        p.name as product_name,
        p.price as selling_price,
        p.cost as purchase_price,
        c.name as category_name,
        CASE 
          WHEN p.cost > 0 THEN ((p.price - p.cost) / p.cost * 100)
          ELSE 0
        END as profit_margin_percent,
        CASE 
          WHEN p.cost > 0 THEN (p.price - p.cost) * i.quantity
          ELSE 0
        END as potential_profit,
        CASE 
          WHEN i.quantity <= i.min_stock_level THEN 1
          ELSE 0
        END as is_low_stock
      FROM inventory i
      JOIN products p ON i.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      ORDER BY is_low_stock DESC, p.name ASC
    ''');
  }
}
