import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore-based database provider for web platform
/// Provides the same interface as DatabaseProvider but uses Firestore instead of SQLite
class FirestoreDatabaseProvider with ChangeNotifier {
  static FirestoreDatabaseProvider? _instance;
  FirebaseFirestore? _firestore;
  bool _isInitialized = false;

  FirestoreDatabaseProvider._();

  factory FirestoreDatabaseProvider() {
    _instance ??= FirestoreDatabaseProvider._();
    return _instance!;
  }

  FirebaseFirestore get firestore {
    if (_firestore == null) {
      throw StateError('Firestore not initialized. Call init() first.');
    }
    return _firestore!;
  }

  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) {
      debugPrint('FirestoreDatabase: Already initialized');
      return;
    }

    try {
      debugPrint('FirestoreDatabase: Initializing Firestore...');

      // Get Firestore instance
      _firestore = FirebaseFirestore.instance;

      // Try to enable offline persistence (may not be supported on all web platforms)
      try {
        _firestore!.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
        debugPrint('FirestoreDatabase: Offline persistence enabled');
      } catch (settingsError) {
        debugPrint(
            'FirestoreDatabase: Could not set persistence settings (this is OK on some web platforms): $settingsError');
        // Continue without persistence settings - Firestore will still work
      }

      // Test Firestore connection with a simple query
      debugPrint('FirestoreDatabase: Testing Firestore connection...');
      try {
        await _firestore!.collection('_test').limit(1).get();
        debugPrint('FirestoreDatabase: Firestore connection test successful');
      } catch (testError) {
        debugPrint('FirestoreDatabase: Connection test failed: $testError');
        // Check if it's a permissions error (database not enabled)
        if (testError.toString().contains('permission') ||
            testError.toString().contains('PERMISSION_DENIED') ||
            testError
                .toString()
                .contains('Missing or insufficient permissions')) {
          throw Exception(
              'Firestore database is not enabled or permissions are not set. Please enable Firestore Database in Firebase Console and configure security rules.');
        }
        // Re-throw other errors
        rethrow;
      }

      _isInitialized = true;
      debugPrint('FirestoreDatabase: Firestore initialized successfully');

      // Initialize default data if needed
      await _initializeDefaultData();
    } catch (e) {
      debugPrint('FirestoreDatabase: Initialization failed: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<int> _deleteCollectionInBatches(
    String collectionName, {
    int batchSize = 400,
  }) async {
    int totalDeleted = 0;
    while (true) {
      final snapshot = await firestore.collection(collectionName).limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      totalDeleted += snapshot.docs.length;
    }
    return totalDeleted;
  }

  Future<void> _initializeDefaultData() async {
    try {
      // Check if settings already exist
      final settingsSnapshot =
          await firestore.collection('settings').limit(1).get();

      if (settingsSnapshot.docs.isEmpty) {
        debugPrint('FirestoreDatabase: Initializing default data...');
        final now = DateTime.now().millisecondsSinceEpoch;

        // Create default settings
        await firestore.collection('settings').doc('cafe_name').set({
          'key': 'cafe_name',
          'value': 'चिया गढी',
          'updated_at': now,
        });

        await firestore.collection('settings').doc('cafe_name_en').set({
          'key': 'cafe_name_en',
          'value': 'Chiya Gadhi',
          'updated_at': now,
        });

        await firestore.collection('settings').doc('tax_percent').set({
          'key': 'tax_percent',
          'value': '13',
          'updated_at': now,
        });

        await firestore.collection('settings').doc('discount_enabled').set({
          'key': 'discount_enabled',
          'value': '1',
          'updated_at': now,
        });

        await firestore
            .collection('settings')
            .doc('default_discount_percent')
            .set({
          'key': 'default_discount_percent',
          'value': '0',
          'updated_at': now,
        });

        await firestore.collection('settings').doc('max_discount_percent').set({
          'key': 'max_discount_percent',
          'value': '50',
          'updated_at': now,
        });

        debugPrint('FirestoreDatabase: Default settings created');
      }
    } catch (e) {
      debugPrint('FirestoreDatabase: Error initializing default data: $e');
      // Don't throw - app can continue without default data
    }
  }

  // Query methods compatible with DatabaseProvider interface
  Future<List<Map<String, dynamic>>> query(
    String collection, {
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
    if (!_isInitialized) {
      await init();
    }

    try {
      // FIXED: Treat "documentId = ?" (and "id = ?" for legacy callers) as direct document lookup.
      // Firestore doesn't store doc id in a field; it's the document key.
      if (where != null &&
          whereArgs != null &&
          whereArgs.length == 1 &&
          (where.trim() == 'documentId = ?' || where.trim() == 'id = ?') &&
          whereArgs.first is String) {
        final docId = whereArgs.first as String;
        final snap = await firestore.collection(collection).doc(docId).get();
        if (!snap.exists) return [];
        final data = snap.data() ?? <String, dynamic>{};
        data['id'] = snap.id;
        return [data];
      }

      Query query = firestore.collection(collection);

      // Apply where clause
      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        // Simple where clause parser for common cases
        // Format: "field = ?" or "field1 = ? AND field2 = ?"
        final conditions = where.split(' AND ');
        for (var i = 0; i < conditions.length && i < whereArgs.length; i++) {
          final condition = conditions[i].trim();
          if (condition.contains(' = ?')) {
            final field = condition.split(' = ?')[0].trim();
            query = query.where(field, isEqualTo: whereArgs[i]);
          } else if (condition.contains(' != ?')) {
            final field = condition.split(' != ?')[0].trim();
            query = query.where(field, isNotEqualTo: whereArgs[i]);
          } else if (condition.contains(' > ?')) {
            final field = condition.split(' > ?')[0].trim();
            query = query.where(field, isGreaterThan: whereArgs[i]);
          } else if (condition.contains(' < ?')) {
            final field = condition.split(' < ?')[0].trim();
            query = query.where(field, isLessThan: whereArgs[i]);
          }
        }
      }

      // Apply orderBy
      if (orderBy != null) {
        // Support multi-field orderBy: "field1 ASC, field2 DESC"
        final segments =
            orderBy.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
        for (final seg in segments) {
          final parts =
              seg.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
          final field = parts.isNotEmpty ? parts[0] : seg;
          final isDesc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';
          query = query.orderBy(field, descending: isDesc);
        }
      }

      // Apply limit
      if (limit != null) {
        query = query.limit(limit);
      }

      // Apply offset
      if (offset != null && offset > 0) {
        query = query.startAfter([offset]);
      }

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // Add document ID as 'id' field for compatibility
        data['id'] = doc.id;
        return data;
      }).toList();
    } on FirebaseException catch (e) {
      // Web frequently hits "failed-precondition: requires an index" for compound queries.
      // Fallback: rerun without orderBy and sort client-side, so app remains usable without indexes.
      debugPrint('FirestoreDatabase: Query error: $e');

      final msg = (e.message ?? '').toLowerCase();
      final isIndexError = e.code == 'failed-precondition' &&
          (msg.contains('requires an index') || msg.contains('index'));

      if (!isIndexError || orderBy == null) {
        rethrow;
      }

      try {
        Query fallbackQuery = firestore.collection(collection);

        // Apply the same where clause (but no orderBy)
        if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
          final conditions = where.split(' AND ');
          for (var i = 0; i < conditions.length && i < whereArgs.length; i++) {
            final condition = conditions[i].trim();
            if (condition.contains(' = ?')) {
              final field = condition.split(' = ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isEqualTo: whereArgs[i]);
            } else if (condition.contains(' != ?')) {
              final field = condition.split(' != ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isNotEqualTo: whereArgs[i]);
            } else if (condition.contains(' > ?')) {
              final field = condition.split(' > ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isGreaterThan: whereArgs[i]);
            } else if (condition.contains(' < ?')) {
              final field = condition.split(' < ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isLessThan: whereArgs[i]);
            }
          }
        }

        if (limit != null) {
          fallbackQuery = fallbackQuery.limit(limit);
        }

        final snap = await fallbackQuery.get();
        final rows = snap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();

        // Sort locally to approximate Firestore orderBy
        _sortRowsInMemory(rows, orderBy);
        return rows;
      } catch (fallbackError) {
        debugPrint('FirestoreDatabase: Query fallback failed: $fallbackError');
        rethrow;
      }
    } catch (e) {
      debugPrint('FirestoreDatabase: Query error: $e');
      rethrow;
    }
  }

  static void _sortRowsInMemory(
      List<Map<String, dynamic>> rows, String orderBy) {
    final segments = orderBy
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    int compareDynamic(dynamic a, dynamic b) {
      if (a == null && b == null) return 0;
      if (a == null) return -1;
      if (b == null) return 1;
      if (a is num && b is num) return a.compareTo(b);
      return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
    }

    rows.sort((ra, rb) {
      for (final seg in segments) {
        final parts =
            seg.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        final field = parts.isNotEmpty ? parts[0] : seg;
        final isDesc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';

        final c = compareDynamic(ra[field], rb[field]);
        if (c != 0) return isDesc ? -c : c;
      }
      // Stable-ish tie-breaker: document id
      return compareDynamic(ra['id'], rb['id']);
    });
  }

  Future<String> insert(String collection, Map<String, dynamic> data) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      // Remove 'id' field if present (Firestore generates it)
      final dataToInsert = Map<String, dynamic>.from(data);
      dataToInsert.remove('id');

      // Add timestamps if not present
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!dataToInsert.containsKey('created_at')) {
        dataToInsert['created_at'] = now;
      }
      if (!dataToInsert.containsKey('updated_at')) {
        dataToInsert['updated_at'] = now;
      }

      final docRef = await firestore.collection(collection).add(dataToInsert);
      debugPrint(
          'FirestoreDatabase: Inserted document ${docRef.id} into $collection');
      return docRef.id;
    } catch (e) {
      debugPrint('FirestoreDatabase: Insert error: $e');
      rethrow;
    }
  }

  Future<int> update(
    String collection, {
    required Map<String, dynamic> data,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      // Add updated_at timestamp
      final dataToUpdate = Map<String, dynamic>.from(data);
      dataToUpdate['updated_at'] = DateTime.now().millisecondsSinceEpoch;

      int count = 0;

      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        // Handle direct documentId update (similar to delete)
        if (where.contains('documentId = ?') && whereArgs.isNotEmpty) {
          final docId = whereArgs[0] as String;
          final docRef = firestore.collection(collection).doc(docId);
          await docRef.update(dataToUpdate);
          count = 1;
          debugPrint(
              'FirestoreDatabase: Updated document $docId in $collection');
        } else {
          // Find documents matching where clause
          final docs =
              await query(collection, where: where, whereArgs: whereArgs);

          // Update each document
          final batch = firestore.batch();
          for (var doc in docs) {
            final docRef =
                firestore.collection(collection).doc(doc['id'] as String);
            batch.update(docRef, dataToUpdate);
            count++;
          }
          await batch.commit();
        }
      } else {
        // Update all documents (use with caution)
        final snapshot = await firestore.collection(collection).get();
        final batch = firestore.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, dataToUpdate);
          count++;
        }
        await batch.commit();
      }

      debugPrint('FirestoreDatabase: Updated $count documents in $collection');
      return count;
    } catch (e) {
      debugPrint('FirestoreDatabase: Update error: $e');
      rethrow;
    }
  }

  Future<int> delete(
    String collection, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      int count = 0;

      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        // FIXED: Handle documentId queries directly (for Firestore)
        if (where.contains('documentId = ?') && whereArgs.isNotEmpty) {
          // Direct delete by document ID
          final docId = whereArgs[0] as String;
          final docRef = firestore.collection(collection).doc(docId);
          await docRef.delete();
          count = 1;
          debugPrint(
              'FirestoreDatabase: Deleted document $docId from $collection');
        } else {
          // Find documents matching where clause
          final docs =
              await query(collection, where: where, whereArgs: whereArgs);

          // Delete each document
          final batch = firestore.batch();
          for (var doc in docs) {
            final docRef =
                firestore.collection(collection).doc(doc['id'] as String);
            batch.delete(docRef);
            count++;
          }
          await batch.commit();
          debugPrint(
              'FirestoreDatabase: Deleted $count documents from $collection');
        }
      } else {
        // Delete all documents (use with caution)
        count = await _deleteCollectionInBatches(collection);
      }

      debugPrint(
          'FirestoreDatabase: Deleted $count documents from $collection');
      return count;
    } catch (e) {
      debugPrint('FirestoreDatabase: Delete error: $e');
      rethrow;
    }
  }

  Future<T?> transaction<T>(Future<T> Function(dynamic txn) action) async {
    if (!_isInitialized) {
      await init();
    }

    try {
      // IMPORTANT (Web): The current transaction wrapper uses normal `.get()` reads inside
      // a Firestore transaction callback, which is not supported on web and can throw
      // opaque JS errors ("Dart exception thrown from converted Future").
      //
      // For web, we run the "transaction" as a best-effort sequential operation wrapper.
      // This keeps the app working reliably without requiring strict atomicity.
      final txnWrapper = _FirestoreNonTransaction(this);
      return await action(txnWrapper);
    } catch (e) {
      debugPrint('FirestoreDatabase: Transaction error: $e');
      rethrow;
    }
  }

  // Reset database (delete all collections)
  Future<void> resetDatabase() async {
    if (!_isInitialized) {
      await init();
    }

    try {
      debugPrint('FirestoreDatabase: Resetting database...');

      // Get all collections
      final collections = [
        'users',
        'orders',
        'order_items',
        'products',
        'categories',
        'customers',
        'settings',
        'inventory',
        'purchases',
        'purchase_items',
        'purchase_payments',
        'expenses',
        'stock_transactions',
        'credit_transactions',
        'payments',
        'tables',
        'day_sessions',
        'audit_log',
        'suppliers',
        'inventory_ledger'
      ];

      int totalDeleted = 0;

      for (final collectionName in collections) {
        totalDeleted += await _deleteCollectionInBatches(collectionName);
      }

      debugPrint(
          'FirestoreDatabase: Reset complete. Deleted $totalDeleted documents');

      // Reinitialize default data
      await _initializeDefaultData();
    } catch (e) {
      debugPrint('FirestoreDatabase: Reset error: $e');
      rethrow;
    }
  }

  /// Clears business data created/entered through the app while keeping
  /// authentication/users and settings intact.
  ///
  /// Note: Firestore deletes are executed in safe batches to avoid the 500 write limit.
  Future<void> clearBusinessData({bool seedDefaults = true}) async {
    if (!_isInitialized) {
      await init();
    }

    // Keep: users, settings
    final collectionsToClear = <String>[
      'orders',
      'order_items',
      'payments',
      'products',
      'categories',
      'customers',
      'inventory',
      'purchases',
      'purchase_items',
      'purchase_payments',
      'expenses',
      'stock_transactions',
      'credit_transactions',
      'tables',
      'day_sessions',
      'audit_log',
      'suppliers',
      'inventory_ledger',
    ];

    int totalDeleted = 0;
    for (final name in collectionsToClear) {
      totalDeleted += await _deleteCollectionInBatches(name);
    }

    debugPrint('FirestoreDatabase: Cleared business data. Deleted $totalDeleted documents');

    if (seedDefaults) {
      // On web, we only seed defaults that are safe to create (settings).
      await _initializeDefaultData();
    }
  }

  Future<void> close() async {
    // Firestore doesn't need explicit closing
    debugPrint('FirestoreDatabase: Close called (no-op for Firestore)');
  }
}

// NOTE: Firestore transaction wrapper removed.
// We intentionally avoid Firestore `runTransaction` on web because it caused
// opaque failures due to invalid read patterns in the old wrapper.

/// Best-effort "transaction" wrapper for Firestore web.
///
/// It provides the minimal API used by services (`insert`, `update`, `query`, `delete`)
/// but executes operations sequentially (no Firestore `runTransaction`).
class _FirestoreNonTransaction {
  final FirestoreDatabaseProvider _db;

  _FirestoreNonTransaction(this._db);

  Future<String> insert(String collection, Map<String, dynamic> data) async {
    return await _db.insert(collection, data);
  }

  Future<int> update(
    String collection,
    dynamic docIdOrData, {
    Map<String, dynamic>? data,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    // SQLite-style: txn.update('table', valuesMap, where: ..., whereArgs: ...)
    if (data == null && docIdOrData is Map<String, dynamic>) {
      return await _db.update(
        collection,
        data: docIdOrData,
        where: where,
        whereArgs: whereArgs,
      );
    }

    // Firestore-style: txn.update('table', docId, dataMap)
    if (docIdOrData is String && data != null) {
      return await _db.update(
        collection,
        data: data,
        where: 'documentId = ?',
        whereArgs: [docIdOrData],
      );
    }

    // Also support txn.update('table', dataMap, where: ..., whereArgs: ...)
    if (data != null) {
      return await _db.update(
        collection,
        data: data,
        where: where,
        whereArgs: whereArgs,
      );
    }

    throw ArgumentError('Invalid update parameters');
  }

  Future<List<Map<String, dynamic>>> query(
    String collection, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return await _db.query(
      collection,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> delete(String collection, String docId) async {
    return await _db.delete(
      collection,
      where: 'documentId = ?',
      whereArgs: [docId],
    );
  }
}
