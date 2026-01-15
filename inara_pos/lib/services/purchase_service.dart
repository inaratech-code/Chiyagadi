import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/unified_database_provider.dart';
import '../providers/auth_provider.dart';
import '../models/purchase_model.dart';
import '../models/purchase_item_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Purchase Service
/// 
/// Handles purchase creation with automatic inventory ledger updates
/// 
/// IMPORTANT RULES:
/// - Purchases CANNOT be deleted (data integrity)
/// - For corrections, use reverse inventory ledger entries
/// - Each purchase item automatically creates an inventory ledger entry
class PurchaseService {
  // Note: Ledger writes are done via the database provider directly.

  /// Generate unique purchase number
  /// Format: PUR yymmdd/000 (same format as orders, but with PUR prefix)
  Future<String> generatePurchaseNumber({
    required BuildContext context,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now();
      // Format: yymmdd (2-digit year, 2-digit month, 2-digit day) - same as orders
      final year = now.year % 100; // Get last 2 digits of year
      final dateStr = '${year.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      
      // Get start and end of today
      final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).millisecondsSinceEpoch;

      // Find all purchases created today with the PUR prefix
      final todayPurchases = await dbProvider.query(
        'purchases',
        where: 'created_at >= ? AND created_at <= ? AND purchase_number LIKE ?',
        whereArgs: [startOfDay, endOfDay, 'PUR $dateStr/%'],
      );
      
      // Extract sequential numbers from today's purchases
      // FIXED: Start from 0 so first purchase is 001 (not 000)
      int maxSequence = 0;
      final pattern = RegExp(r'PUR \d{6}/(\d+)');
      
      for (final purchase in todayPurchases) {
        final purchaseNumber = purchase['purchase_number'] as String;
        final match = pattern.firstMatch(purchaseNumber);
        if (match != null) {
          final sequence = int.tryParse(match.group(1) ?? '0') ?? 0;
          if (sequence > maxSequence) {
            maxSequence = sequence;
          }
        }
      }
      
      // Increment sequence number (start from 001)
      final nextSequence = maxSequence + 1;
      final sequenceStr = nextSequence.toString().padLeft(3, '0');
      
      return 'PUR $dateStr/$sequenceStr';
    } catch (e) {
      debugPrint('Error generating purchase number: $e');
      // Fallback to timestamp-based number (start from 001)
      final now = DateTime.now();
      final year = now.year % 100;
      final dateStr = '${year.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      return 'PUR $dateStr/001';
    }
  }

  /// Create a new purchase with items
  /// 
  /// This method:
  /// 1. Creates the purchase record
  /// 2. Creates purchase items
  /// 3. Creates inventory ledger entries for each item
  /// 4. Updates product costs (average cost method)
  /// 
  /// All operations are done in a transaction for data integrity
  Future<dynamic> createPurchase({
    required BuildContext context,
    required dynamic supplierId,
    required String? supplierName,
    String? billNumber,
    required List<PurchaseItem> items,
    double? discountAmount,
    double? taxAmount,
    String? notes,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await dbProvider.init();

      // Validate items
      if (items.isEmpty) {
        throw Exception('Purchase must have at least one item');
      }

      // Calculate total
      double totalAmount = items.fold(0.0, (sum, item) => sum + item.totalPrice);
      totalAmount -= (discountAmount ?? 0.0);
      totalAmount += (taxAmount ?? 0.0);

      // Generate purchase number
      final purchaseNumber = await generatePurchaseNumber(context: context);

      final now = DateTime.now().millisecondsSinceEpoch;
      // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
      final createdBy = authProvider.currentUserId != null
          ? (kIsWeb ? authProvider.currentUserId! : int.tryParse(authProvider.currentUserId!))
          : null;

      // Use transaction to ensure all operations succeed or fail together
      final purchaseId = await dbProvider.transaction((txn) async {
        // 1. Create purchase record
        final purchaseId = await txn.insert('purchases', {
          'supplier_id': supplierId,
          'supplier_name': supplierName,
          'purchase_number': purchaseNumber,
          'bill_number': billNumber,
          'total_amount': totalAmount,
          'discount_amount': discountAmount,
          'tax_amount': taxAmount,
          'paid_amount': 0.0,
          'outstanding_amount': totalAmount,
          'payment_status': 'unpaid',
          'notes': notes,
          'status': 'completed',
          'created_by': createdBy,
          'created_at': now,
          'updated_at': now,
        });

        // 2. Create purchase items and inventory ledger entries
        for (final item in items) {
          // Insert purchase item
          await txn.insert('purchase_items', {
            'purchase_id': purchaseId,
            'product_id': item.productId,
            'product_name': item.productName,
            'unit': item.unit,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'total_price': item.totalPrice,
            'notes': item.notes,
          });

          // Create inventory ledger entry (quantityIn = purchased quantity)
          await txn.insert('inventory_ledger', {
            'product_id': item.productId,
            'product_name': item.productName,
            'unit': item.unit,
            'quantity_in': item.quantity, // Stock increase
            'quantity_out': 0.0, // No stock decrease
            'unit_price': item.unitPrice,
            'transaction_type': 'purchase',
            'reference_type': 'purchase',
            'reference_id': purchaseId,
            'notes': notes,
            'created_by': createdBy,
            'created_at': now,
          });

          // Update product cost (average cost method) - only for SQLite
          // For Firestore, we'll update cost after transaction
          if (!kIsWeb) {
            await _updateProductCost(txn, item.productId, item.unitPrice, item.quantity);
          }
        }

        return purchaseId;
      });
      
      // For Firestore, update product costs after transaction
      if (kIsWeb) {
        for (final item in items) {
          await _updateProductCostAfterTransaction(dbProvider, item.productId, item.unitPrice, item.quantity);
        }
      }
      
      return purchaseId;
    } catch (e) {
      debugPrint('Error creating purchase: $e');
      rethrow;
    }
  }

  /// Update product cost using average cost method
  /// 
  /// New Average Cost = (Old Cost * Old Quantity + New Cost * New Quantity) / (Old Quantity + New Quantity)
  /// 
  /// Note: For Firestore transactions, we need to get the product before the transaction
  /// and calculate stock from the database provider directly
  Future<void> _updateProductCost(
    dynamic txn,
    dynamic productId,
    double newUnitPrice,
    double newQuantity,
  ) async {
    try {
      // For Firestore, we can't query within transaction, so we'll update cost after transaction
      // For SQLite, we can query within transaction
      if (kIsWeb) {
        // Firestore: Get product and ledger data before transaction or use a workaround
        // For now, we'll skip cost update in transaction and do it after
        // This is acceptable as cost update is not critical for purchase creation
        return;
      } else {
        // SQLite: Can query within transaction
        // Get current product
        final products = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
        );

        if (products.isEmpty) return;

        final product = products.first;
        final currentCost = (product['cost'] as num?)?.toDouble() ?? 0.0;

        // Get current stock from ledger
        final ledgerEntries = await txn.query(
          'inventory_ledger',
          where: 'product_id = ?',
          whereArgs: [productId],
        );

        double currentQuantity = 0.0;
        for (final entry in ledgerEntries) {
          currentQuantity += (entry['quantity_in'] as num?)?.toDouble() ?? 0.0;
          currentQuantity -= (entry['quantity_out'] as num?)?.toDouble() ?? 0.0;
        }

        // Calculate new average cost
        double newCost;
        if (currentQuantity <= 0) {
          // No existing stock, use new price
          newCost = newUnitPrice;
        } else {
          // Average cost method
          final totalOldValue = currentCost * currentQuantity;
          final totalNewValue = newUnitPrice * newQuantity;
          final totalQuantity = currentQuantity + newQuantity;
          newCost = (totalOldValue + totalNewValue) / totalQuantity;
        }

        // Update product cost
        await txn.update(
          'products',
          values: {
            'cost': newCost,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
    } catch (e) {
      debugPrint('Error updating product cost: $e');
      // Don't throw - cost update failure shouldn't fail the purchase
    }
  }

  /// Update product cost after transaction (for Firestore)
  Future<void> _updateProductCostAfterTransaction(
    UnifiedDatabaseProvider dbProvider,
    dynamic productId,
    double newUnitPrice,
    double newQuantity,
  ) async {
    try {
      // Get current product
      final products = await dbProvider.query(
        'products',
        where: 'documentId = ?',
        whereArgs: [productId],
      );

      if (products.isEmpty) return;

      final product = products.first;
      final currentCost = (product['cost'] as num?)?.toDouble() ?? 0.0;

      // Get current stock from ledger
      final ledgerEntries = await dbProvider.query(
        'inventory_ledger',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      double currentQuantity = 0.0;
      for (final entry in ledgerEntries) {
        currentQuantity += (entry['quantity_in'] as num?)?.toDouble() ?? 0.0;
        currentQuantity -= (entry['quantity_out'] as num?)?.toDouble() ?? 0.0;
      }

      // Calculate new average cost
      double newCost;
      if (currentQuantity <= 0) {
        // No existing stock, use new price
        newCost = newUnitPrice;
      } else {
        // Average cost method
        final totalOldValue = currentCost * currentQuantity;
        final totalNewValue = newUnitPrice * newQuantity;
        final totalQuantity = currentQuantity + newQuantity;
        newCost = (totalOldValue + totalNewValue) / totalQuantity;
      }

      // Update product cost
      await dbProvider.update(
        'products',
        values: {
          'cost': newCost,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'documentId = ?',
        whereArgs: [productId],
      );
    } catch (e) {
      debugPrint('Error updating product cost after transaction: $e');
      // Don't throw - cost update failure shouldn't fail the purchase
    }
  }

  /// Get purchase by ID
  Future<Purchase?> getPurchaseById({
    required BuildContext context,
    required dynamic purchaseId,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final purchases = await dbProvider.query(
        'purchases',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [purchaseId],
      );

      if (purchases.isEmpty) return null;

      return Purchase.fromMap(purchases.first);
    } catch (e) {
      debugPrint('Error getting purchase: $e');
      return null;
    }
  }

  /// Get purchase items for a purchase
  Future<List<PurchaseItem>> getPurchaseItems({
    required BuildContext context,
    required dynamic purchaseId,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final items = await dbProvider.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
      );

      return items.map((item) => PurchaseItem.fromMap(item)).toList();
    } catch (e) {
      debugPrint('Error getting purchase items: $e');
      return [];
    }
  }

  /// Get all purchases
  Future<List<Purchase>> getAllPurchases({
    required BuildContext context,
    int? limit,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final purchases = await dbProvider.query(
        'purchases',
        orderBy: 'created_at DESC',
        limit: limit,
      );

      return purchases.map((p) => Purchase.fromMap(p)).toList();
    } catch (e) {
      debugPrint('Error getting purchases: $e');
      return [];
    }
  }
}
