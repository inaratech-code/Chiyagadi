import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/unified_database_provider.dart';
import '../models/supplier_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Supplier Service
/// Handles supplier CRUD operations
class SupplierService {
  /// Find a supplier by name (best-effort; includes case-insensitive fallback)
  Future<Supplier?> getSupplierByName({
    required BuildContext context,
    required String name,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final trimmed = name.trim();
      if (trimmed.isEmpty) return null;

      // Fast path: exact match
      final exact = await dbProvider.query(
        'suppliers',
        where: 'name = ?',
        whereArgs: [trimmed],
      );
      if (exact.isNotEmpty) {
        return Supplier.fromMap(exact.first);
      }

      // Fallback: case-insensitive match in memory (works for both SQLite + Firestore)
      final all = await dbProvider.query('suppliers');
      final lowered = trimmed.toLowerCase();
      for (final row in all) {
        try {
          final s = Supplier.fromMap(row);
          if (s.name.trim().toLowerCase() == lowered) return s;
        } catch (_) {
          // ignore bad rows
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting supplier by name: $e');
      return null;
    }
  }

  /// Get (or create) supplier ID by name.
  /// Returns int (SQLite) on mobile and String (Firestore documentId) on web.
  Future<dynamic> getOrCreateSupplierIdByName({
    required BuildContext context,
    required String supplierName,
  }) async {
    final trimmed = supplierName.trim();
    if (trimmed.isEmpty) {
      throw Exception('Supplier name is required');
    }

    final existing = await getSupplierByName(context: context, name: trimmed);
    if (existing != null) {
      return kIsWeb ? (existing.documentId ?? existing.id?.toString()) : existing.id;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    await dbProvider.init();

    // Create minimal supplier
    return await dbProvider.insert('suppliers', {
      'name': trimmed,
      'contact_person': null,
      'phone': null,
      'email': null,
      'address': null,
      'notes': null,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Get all suppliers
  Future<List<Supplier>> getAllSuppliers({
    required BuildContext context,
    bool activeOnly = false,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final suppliers = await dbProvider.query(
        'suppliers',
        where: activeOnly ? 'is_active = ?' : null,
        whereArgs: activeOnly ? [1] : null,
        orderBy: 'name ASC',
      );

      return suppliers.map((s) => Supplier.fromMap(s)).toList();
    } catch (e) {
      debugPrint('Error getting suppliers: $e');
      return [];
    }
  }

  /// Get supplier by ID
  Future<Supplier?> getSupplierById({
    required BuildContext context,
    required dynamic supplierId,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final suppliers = await dbProvider.query(
        'suppliers',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [supplierId],
      );

      if (suppliers.isEmpty) return null;

      return Supplier.fromMap(suppliers.first);
    } catch (e) {
      debugPrint('Error getting supplier: $e');
      return null;
    }
  }

  /// Create a new supplier
  Future<dynamic> createSupplier({
    required BuildContext context,
    required Supplier supplier,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now().millisecondsSinceEpoch;

      final supplierId = await dbProvider.insert('suppliers', {
        'name': supplier.name,
        'contact_person': supplier.contactPerson,
        'phone': supplier.phone,
        'email': supplier.email,
        'address': supplier.address,
        'notes': supplier.notes,
        'is_active': supplier.isActive ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      });

      return supplierId;
    } catch (e) {
      debugPrint('Error creating supplier: $e');
      rethrow;
    }
  }

  /// Update supplier
  Future<void> updateSupplier({
    required BuildContext context,
    required dynamic supplierId,
    required Supplier supplier,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now().millisecondsSinceEpoch;

      await dbProvider.update(
        'suppliers',
        values: {
          'name': supplier.name,
          'contact_person': supplier.contactPerson,
          'phone': supplier.phone,
          'email': supplier.email,
          'address': supplier.address,
          'notes': supplier.notes,
          'is_active': supplier.isActive ? 1 : 0,
          'updated_at': now,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [supplierId],
      );
    } catch (e) {
      debugPrint('Error updating supplier: $e');
      rethrow;
    }
  }

  /// Delete supplier (soft delete by setting is_active = false)
  Future<void> deleteSupplier({
    required BuildContext context,
    required dynamic supplierId,
  }) async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now().millisecondsSinceEpoch;

      await dbProvider.update(
        'suppliers',
        values: {
          'is_active': 0,
          'updated_at': now,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [supplierId],
      );
    } catch (e) {
      debugPrint('Error deleting supplier: $e');
      rethrow;
    }
  }
}
