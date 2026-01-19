import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/unified_database_provider.dart';
import '../models/inventory_ledger_model.dart';

/// Inventory Ledger Service
///
/// IMPORTANT: Stock is NEVER stored directly in the product or inventory table.
/// Stock is ALWAYS calculated from the inventory_ledger entries.
///
/// Current Stock Formula:
/// Current Stock = Sum(quantityIn) - Sum(quantityOut)
///
/// This ensures data integrity and provides a complete audit trail.
class InventoryLedgerService {
  /// Get current stock for a product by calculating from ledger
  ///
  /// This is the ONLY way to get stock - it's calculated, not stored
  Future<double> getCurrentStock({
    required BuildContext context,
    required dynamic productId,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Get all ledger entries for this product
      final ledgerEntries = await dbProvider.query(
        'inventory_ledger',
        where: 'product_id = ?',
        whereArgs: [productId],
      );

      // Calculate stock: Sum(quantityIn) - Sum(quantityOut)
      double totalIn = 0.0;
      double totalOut = 0.0;

      for (final entry in ledgerEntries) {
        totalIn += (entry['quantity_in'] as num?)?.toDouble() ?? 0.0;
        totalOut += (entry['quantity_out'] as num?)?.toDouble() ?? 0.0;
      }

      return totalIn - totalOut;
    } catch (e) {
      debugPrint('Error calculating current stock: $e');
      return 0.0;
    }
  }

  /// Get current stock for multiple products (batch calculation)
  Future<Map<dynamic, double>> getCurrentStockBatch({
    required BuildContext context,
    required List<dynamic> productIds,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Initialize result map with zeros
      final Map<dynamic, double> stockMap = {};
      for (final productId in productIds) {
        stockMap[productId] = 0.0;
      }

      if (productIds.isEmpty) return stockMap;

      // Get all ledger entries for these products.
      // With Firestore `IN (...)` support, we can use the same approach on web and mobile.
      final placeholders = List.filled(productIds.length, '?').join(',');
      final ledgerEntries = await dbProvider.query(
        'inventory_ledger',
        where: 'product_id IN ($placeholders)',
        whereArgs: productIds,
      );

      // Group by product_id and calculate
      for (final entry in ledgerEntries) {
        final productId = entry['product_id'];
        if (!stockMap.containsKey(productId)) {
          stockMap[productId] = 0.0;
        }

        stockMap[productId] = (stockMap[productId] ?? 0.0) +
            ((entry['quantity_in'] as num?)?.toDouble() ?? 0.0) -
            ((entry['quantity_out'] as num?)?.toDouble() ?? 0.0);
      }

      return stockMap;
    } catch (e) {
      debugPrint('Error calculating batch stock: $e');
      return {};
    }
  }

  /// Add inventory ledger entry (for purchases, adjustments, etc.)
  ///
  /// This is the ONLY way to increase stock - through ledger entries
  Future<void> addLedgerEntry({
    required BuildContext context,
    required InventoryLedger ledgerEntry,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now().millisecondsSinceEpoch;

      await dbProvider.insert('inventory_ledger', {
        'product_id': ledgerEntry.productId,
        'product_name': ledgerEntry.productName,
        'quantity_in': ledgerEntry.quantityIn,
        'quantity_out': ledgerEntry.quantityOut,
        'unit_price': ledgerEntry.unitPrice,
        'transaction_type': ledgerEntry.transactionType,
        'reference_type': ledgerEntry.referenceType,
        'reference_id': ledgerEntry.referenceId,
        'notes': ledgerEntry.notes,
        'created_by': ledgerEntry.createdBy,
        'created_at': now,
      });
    } catch (e) {
      debugPrint('Error adding ledger entry: $e');
      rethrow;
    }
  }

  /// Add multiple ledger entries in a transaction (for batch operations)
  Future<void> addLedgerEntriesBatch({
    required BuildContext context,
    required List<InventoryLedger> ledgerEntries,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now().millisecondsSinceEpoch;

      // Use transaction to ensure all entries are added atomically
      await dbProvider.transaction((txn) async {
        for (final entry in ledgerEntries) {
          await txn.insert('inventory_ledger', {
            'product_id': entry.productId,
            'product_name': entry.productName,
            'quantity_in': entry.quantityIn,
            'quantity_out': entry.quantityOut,
            'unit_price': entry.unitPrice,
            'transaction_type': entry.transactionType,
            'reference_type': entry.referenceType,
            'reference_id': entry.referenceId,
            'notes': entry.notes,
            'created_by': entry.createdBy,
            'created_at': now,
          });
        }
      });
    } catch (e) {
      debugPrint('Error adding batch ledger entries: $e');
      rethrow;
    }
  }

  /// Get ledger history for a product
  Future<List<InventoryLedger>> getLedgerHistory({
    required BuildContext context,
    required dynamic productId,
    int? limit,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final entries = await dbProvider.query(
        'inventory_ledger',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'created_at DESC',
        limit: limit,
      );

      return entries.map((e) => InventoryLedger.fromMap(e)).toList();
    } catch (e) {
      debugPrint('Error getting ledger history: $e');
      return [];
    }
  }

  /// Create a reverse/correction entry for a purchase
  ///
  /// Since purchases cannot be deleted, we create a reverse entry
  /// to correct any mistakes
  Future<void> createReverseEntry({
    required BuildContext context,
    required InventoryLedger originalEntry,
    required String reason,
    int? createdBy,
  }) async {
    try {
      final reverseEntry = InventoryLedger(
        productId: originalEntry.productId,
        productName: originalEntry.productName,
        quantityIn:
            originalEntry.quantityOut, // Reverse: what was out becomes in
        quantityOut:
            originalEntry.quantityIn, // Reverse: what was in becomes out
        unitPrice: originalEntry.unitPrice,
        transactionType: 'correction',
        referenceType: originalEntry.referenceType,
        referenceId: originalEntry.referenceId,
        notes: 'Correction: $reason',
        createdBy: createdBy,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      await addLedgerEntry(context: context, ledgerEntry: reverseEntry);
    } catch (e) {
      debugPrint('Error creating reverse entry: $e');
      rethrow;
    }
  }
}
