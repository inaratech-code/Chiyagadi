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
        debugPrint('FirestoreDatabase: Could not set persistence settings (this is OK on some web platforms): $settingsError');
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
            testError.toString().contains('Missing or insufficient permissions')) {
          throw Exception('Firestore database is not enabled or permissions are not set. Please enable Firestore Database in Firebase Console and configure security rules.');
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

  Future<void> _initializeDefaultData() async {
    try {
      // Check if settings already exist
      final settingsSnapshot = await firestore.collection('settings').limit(1).get();
      
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
        
        await firestore.collection('settings').doc('default_discount_percent').set({
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
        final parts = orderBy.split(' ');
        final field = parts[0];
        final direction = parts.length > 1 && parts[1].toUpperCase() == 'DESC'
            ? 'desc'
            : 'asc';
        query = query.orderBy(field, descending: direction == 'desc');
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
    } catch (e) {
      debugPrint('FirestoreDatabase: Query error: $e');
      rethrow;
    }
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
      debugPrint('FirestoreDatabase: Inserted document ${docRef.id} into $collection');
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
          debugPrint('FirestoreDatabase: Updated document $docId in $collection');
        } else {
          // Find documents matching where clause
          final docs = await query(collection, where: where, whereArgs: whereArgs);
          
          // Update each document
          final batch = firestore.batch();
          for (var doc in docs) {
            final docRef = firestore.collection(collection).doc(doc['id'] as String);
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
          debugPrint('FirestoreDatabase: Deleted document $docId from $collection');
        } else {
          // Find documents matching where clause
          final docs = await query(collection, where: where, whereArgs: whereArgs);
          
          // Delete each document
          final batch = firestore.batch();
          for (var doc in docs) {
            final docRef = firestore.collection(collection).doc(doc['id'] as String);
            batch.delete(docRef);
            count++;
          }
          await batch.commit();
          debugPrint('FirestoreDatabase: Deleted $count documents from $collection');
        }
      } else {
        // Delete all documents (use with caution)
        final snapshot = await firestore.collection(collection).get();
        final batch = firestore.batch();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
          count++;
        }
        await batch.commit();
      }

      debugPrint('FirestoreDatabase: Deleted $count documents from $collection');
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
      return await firestore.runTransaction((transaction) async {
        // Create a wrapper to match the expected interface
        final txnWrapper = _FirestoreTransaction(transaction, firestore);
        return await action(txnWrapper);
      });
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
      final collections = ['users', 'orders', 'order_items', 'products', 'categories', 
                          'customers', 'settings', 'inventory', 'purchases', 
                          'purchase_items', 'purchase_payments', 'stock_transactions', 'credit_transactions', 
                          'payments', 'tables', 'day_sessions', 'audit_log',
                          'suppliers', 'inventory_ledger'];
      
      final batch = firestore.batch();
      int totalDeleted = 0;
      
      for (final collectionName in collections) {
        final snapshot = await firestore.collection(collectionName).get();
        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
          totalDeleted++;
        }
      }
      
      await batch.commit();
      debugPrint('FirestoreDatabase: Reset complete. Deleted $totalDeleted documents');
      
      // Reinitialize default data
      await _initializeDefaultData();
    } catch (e) {
      debugPrint('FirestoreDatabase: Reset error: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    // Firestore doesn't need explicit closing
    debugPrint('FirestoreDatabase: Close called (no-op for Firestore)');
  }
}

/// Wrapper class to make Firestore Transaction compatible with expected interface
/// 
/// FIXED: Added query support and update with where clause support
class _FirestoreTransaction {
  final Transaction _transaction;
  final FirebaseFirestore _firestore;

  _FirestoreTransaction(this._transaction, this._firestore);

  Future<String> insert(String collection, Map<String, dynamic> data) async {
    final docRef = _firestore.collection(collection).doc();
    final dataToInsert = Map<String, dynamic>.from(data);
    dataToInsert.remove('id');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!dataToInsert.containsKey('created_at')) {
      dataToInsert['created_at'] = now;
    }
    if (!dataToInsert.containsKey('updated_at')) {
      dataToInsert['updated_at'] = now;
    }
    _transaction.set(docRef, dataToInsert);
    return docRef.id;
  }

  /// FIXED: Support both direct docId update and where clause update
  Future<int> update(
    String collection,
    dynamic docIdOrData, {
    Map<String, dynamic>? data,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    // Handle SQLite-style update (data, where, whereArgs)
    if (data != null && where != null && whereArgs != null) {
      // Query to get document ID first
      final query = _firestore.collection(collection);
      Query queryRef = query;
      
      // Parse where clause (simple support for 'field = ?')
      if (where.contains('=') && whereArgs.isNotEmpty) {
        final field = where.split('=')[0].trim();
        final value = whereArgs[0];
        queryRef = queryRef.where(field, isEqualTo: value);
      }
      
      // Get document snapshot (this must be done before transaction)
      // Note: Firestore transactions require all reads before writes
      final snapshot = await queryRef.get();
      if (snapshot.docs.isEmpty) {
        return 0;
      }
      
      final docRef = snapshot.docs.first.reference;
      final dataToUpdate = Map<String, dynamic>.from(data);
      dataToUpdate['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      _transaction.update(docRef, dataToUpdate);
      return 1;
    }
    
    // Handle Firestore-style update (collection, docId, data)
    if (docIdOrData is String && data != null) {
      final docRef = _firestore.collection(collection).doc(docIdOrData);
      final dataToUpdate = Map<String, dynamic>.from(data);
      dataToUpdate['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      _transaction.update(docRef, dataToUpdate);
      return 1;
    }
    
    throw ArgumentError('Invalid update parameters');
  }

  /// FIXED: Added query support for transactions
  /// Note: In Firestore, all reads must happen before writes in a transaction
  Future<List<Map<String, dynamic>>> query(
    String collection, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    Query queryRef = _firestore.collection(collection);
    
    if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
      // FIXED: Allow direct doc lookup inside transactions too
      if (whereArgs.length == 1 &&
          (where.trim() == 'documentId = ?' || where.trim() == 'id = ?') &&
          whereArgs.first is String) {
        final docId = whereArgs.first as String;
        final docSnap = await _firestore.collection(collection).doc(docId).get();
        if (!docSnap.exists) return [];
        final data = docSnap.data() ?? <String, dynamic>{};
        data['id'] = docSnap.id;
        return [data];
      }

      // Parse simple where clause (e.g., 'field = ?')
      if (where.contains('=')) {
        final parts = where.split('=');
        if (parts.length == 2) {
          final field = parts[0].trim();
          final value = whereArgs[0];
          queryRef = queryRef.where(field, isEqualTo: value);
        }
      }
    }
    
    final snapshot = await queryRef.get();
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id; // Add document ID
      return data;
    }).toList();
  }

  Future<int> delete(String collection, String docId) async {
    final docRef = _firestore.collection(collection).doc(docId);
    _transaction.delete(docRef);
    return 1;
  }
}
