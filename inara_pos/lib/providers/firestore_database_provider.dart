import 'dart:async';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/chiyagaadi_menu_seed.dart';

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
      // Try to get instance if not set (defensive fallback)
      try {
        _firestore = FirebaseFirestore.instance;
        if (_firestore == null) {
          throw StateError('Firestore not initialized. Call init() first.');
        }
      } catch (e) {
        throw StateError('Firestore not initialized. Call init() first. Error: $e');
      }
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

      // CRITICAL: Ensure Firebase is initialized before accessing Firestore
      if (Firebase.apps.isEmpty) {
        throw StateError(
          'Firebase is not initialized. Please ensure Firebase.initializeApp() is called first.\n\n'
          'This should be done in UnifiedDatabaseProvider.init() before calling FirestoreDatabaseProvider.init().'
        );
      }

      debugPrint('FirestoreDatabase: Firebase apps count: ${Firebase.apps.length}');

      // Get Firestore instance with defensive error handling and retries
      // iOS Safari sometimes needs multiple delays after Firebase.initializeApp()
      FirebaseFirestore? firestoreInstance;
      int maxRetries = 3;
      int retryDelayMs = 50; // FIXED: Reduced from 200ms to 50ms for faster startup
      
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          // Progressive delay: shorter wait on each retry for faster startup
          if (attempt > 0) {
            final delayMs = retryDelayMs * (attempt + 1);
            debugPrint('FirestoreDatabase: Retry attempt $attempt, waiting ${delayMs}ms...');
            await Future.delayed(Duration(milliseconds: delayMs));
          } else if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
            // FIXED: Reduced initial delay for iOS Safari
            await Future.delayed(const Duration(milliseconds: 50));
          }
          
          // Verify Firebase is still initialized
          if (Firebase.apps.isEmpty) {
            throw StateError('Firebase apps became empty during initialization');
          }
          
          // Try to get Firestore instance using dynamic access to avoid minified JS errors
          try {
            dynamic firestoreInstance;
            try {
              firestoreInstance = FirebaseFirestore.instance;
            } catch (e) {
              debugPrint('FirestoreDatabase: Error accessing FirebaseFirestore.instance: $e');
              // If it's a minified JS error, wait and retry
              if (e.toString().contains('minified') || e.toString().contains('TypeError')) {
                debugPrint('FirestoreDatabase: Minified JS error detected, waiting longer before retry...');
                // FIXED: Reduced delay for faster retry
                await Future.delayed(Duration(milliseconds: 50 * (attempt + 1)));
                // Try again
                firestoreInstance = FirebaseFirestore.instance;
              } else {
                rethrow;
              }
            }
            
            // Verify instance is not null
            if (firestoreInstance == null) {
              throw StateError('FirebaseFirestore.instance returned null');
            }
            
            // Try a simple operation to verify it's actually working
            // This will catch any underlying initialization issues
            try {
              // Just check if we can access the instance without error
              final _ = firestoreInstance.collection('_test').limit(0);
            } catch (testError) {
              debugPrint('FirestoreDatabase: Test access failed (non-critical): $testError');
              // Don't fail on test - might be permission issue, but instance is valid
            }
            
            // Success!
            _firestore = firestoreInstance;
            debugPrint('FirestoreDatabase: Firestore instance obtained successfully on attempt ${attempt + 1}');
            break; // Exit retry loop
          } catch (instanceError) {
            final instanceErrorMsg = instanceError.toString();
            debugPrint('FirestoreDatabase: Attempt ${attempt + 1} failed: $instanceError');
            
            // If this is the last attempt, throw the error
            if (attempt == maxRetries - 1) {
              if (instanceErrorMsg.contains('Null check operator') || 
                  instanceErrorMsg.contains('null value') ||
                  instanceErrorMsg.contains('NoSuchMethodError') ||
                  instanceErrorMsg.contains('minified') ||
                  instanceErrorMsg.contains('TypeError')) {
                // For minified JS errors, try one more time with a shorter delay
                debugPrint('FirestoreDatabase: Minified JS/null check error on final attempt, trying one more time...');
                await Future.delayed(const Duration(milliseconds: 200)); // FIXED: Reduced from 1000ms to 200ms
                try {
                  final lastAttempt = FirebaseFirestore.instance;
                  _firestore = lastAttempt;
                  debugPrint('FirestoreDatabase: Firestore instance obtained on final retry');
                  break;
                } catch (finalError) {
                  throw StateError(
                    'Firestore initialization failed after $maxRetries attempts + final retry.\n\n'
                    'This is often caused by:\n'
                    '1. Firebase not fully initialized on iOS Safari\n'
                    '2. Firestore Database not enabled in Firebase Console\n'
                    '3. Browser compatibility issue\n'
                    '4. Firestore security rules require authentication\n\n'
                    'Try:\n'
                    '1. Hard refresh the page (Cmd+Shift+R on Mac, Ctrl+Shift+R on Windows)\n'
                    '2. Clear browser cache\n'
                    '3. Check Firebase Console to ensure Firestore is enabled\n'
                    '4. Update Firestore rules to allow public access temporarily\n\n'
                    'Original error: $instanceError\n'
                    'Final retry error: $finalError'
                  );
                }
              }
              rethrow;
            }
            // Otherwise, continue to next retry
          }
        } catch (e) {
          final errorMsg = e.toString();
          debugPrint('FirestoreDatabase: Failed on attempt ${attempt + 1}: $e');
          
          // If this is the last attempt, throw
          if (attempt == maxRetries - 1) {
            if (errorMsg.contains('Null check operator') || errorMsg.contains('null value')) {
              throw StateError(
                'Firestore initialization failed after $maxRetries attempts.\n\n'
                'This may be due to:\n'
                '1. Firebase not fully initialized (try refreshing)\n'
                '2. Firestore not enabled in Firebase Console\n'
                '3. Browser compatibility issue\n\n'
                'Original error: $e'
              );
            }
            throw StateError('Failed to get Firestore instance after $maxRetries attempts: $e');
          }
          // Continue to next retry
        }
      }
      
      // Final check
      if (_firestore == null) {
        throw StateError('Firestore instance is null after all retry attempts');
      }
      
      debugPrint('FirestoreDatabase: Firestore instance obtained');

      // Web/iOS Safari often fails (or behaves inconsistently) with persistence enabled.
      // This can surface as opaque "Null check operator used on a null value" errors on new devices.
      //
      // Strategy:
      // - On web+iOS: force persistence OFF for reliability.
      // - Elsewhere: best-effort enable persistence; if it fails, fall back to OFF.
      final isWebIOS = kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      if (isWebIOS) {
        try {
          _firestore?.settings = const Settings(
            persistenceEnabled: false,
          );
          debugPrint(
              'FirestoreDatabase: Web iOS detected, persistence disabled for stability');
        } catch (e) {
          debugPrint(
              'FirestoreDatabase: Failed to apply iOS web settings (continuing): $e');
        }
      } else {
        try {
          _firestore?.settings = const Settings(
            persistenceEnabled: true,
            cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          );
          debugPrint('FirestoreDatabase: Offline persistence enabled');
        } catch (settingsError) {
          debugPrint(
              'FirestoreDatabase: Could not enable persistence; falling back to disabled: $settingsError');
          try {
            _firestore?.settings = const Settings(
              persistenceEnabled: false,
            );
          } catch (_) {
            // Ignore: Firestore will still work with defaults.
          }
        }
      }

      // Test Firestore connectivity with a simple read operation
      try {
        debugPrint('FirestoreDatabase: Testing Firestore connectivity...');
        final testQuery = await _firestore!.collection('_connectivity_test').limit(1).get();
        debugPrint('FirestoreDatabase: Connectivity test successful - Firestore is accessible');
      } catch (testError) {
        final testErrorMsg = testError.toString();
        debugPrint('FirestoreDatabase: Connectivity test failed: $testError');
        
        // If it's a permissions error, that's okay - Firestore is initialized
        if (testErrorMsg.contains('permission') || 
            testErrorMsg.contains('PERMISSION_DENIED') ||
            testErrorMsg.contains('Missing or insufficient permissions')) {
          debugPrint('FirestoreDatabase: Permission error (expected if rules require auth) - Firestore is initialized');
        } else {
          debugPrint('FirestoreDatabase: Warning - Connectivity test failed but continuing anyway');
        }
      }
      
      _isInitialized = true;
      debugPrint('FirestoreDatabase: Firestore initialized successfully');

      // PERF: Do not block app startup on network checks / seeding.
      // We'll validate connectivity and seed defaults in the background.
      unawaited(() async {
        // Best-effort connection check
        try {
          final fs = _firestore;
          if (fs != null) {
            debugPrint('FirestoreDatabase: Background connection test...');
            await fs.collection('_test').limit(1).get();
            debugPrint('FirestoreDatabase: Background connection test ok');
          }
        } catch (e) {
          debugPrint('FirestoreDatabase: Background connection test failed: $e');
        }

        // Best-effort default data init
        try {
          final fs = _firestore;
          if (fs != null) {
            await _initializeDefaultData();
          }
        } catch (e) {
          debugPrint('FirestoreDatabase: Background seed failed: $e');
        }
      }());
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
      final snapshot =
          await firestore.collection(collectionName).limit(batchSize).get();
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

      // Ensure menu seed exists (adds missing items without duplicating).
      await _ensureChiyagaadiMenuSeed();
    } catch (e) {
      debugPrint('FirestoreDatabase: Error initializing default data: $e');
      // Don't throw - app can continue without default data
    }
  }

  /// Public method to seed menu items - can be called manually
  Future<void> seedMenuItems() async {
    await _ensureChiyagaadiMenuSeed();
  }
  
  Future<void> _ensureChiyagaadiMenuSeed() async {
    debugPrint('FirestoreDatabase: Ensuring Chiyagaadi menu seed...');
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      // Use multiple batches if needed (Firestore limit is 500 operations per batch)
      final List<WriteBatch> batches = [firestore.batch()];
      int currentBatchIndex = 0;
      int operationsInCurrentBatch = 0;
      const maxBatchSize = 450; // Stay under 500 limit

      String norm(String s) =>
          s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

      // Ensure categories exist (by exact name match first, then normalized as fallback)
      final Map<String, String> categoryIdByNormName = {};
      int categoriesToAdd = 0;
      
      for (final cat in chiyagaadiSeedCategories) {
        final snap = await firestore
            .collection('categories')
            .where('name', isEqualTo: cat.name)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          categoryIdByNormName[norm(cat.name)] = snap.docs.first.id;
          debugPrint('FirestoreDatabase: Category "${cat.name}" already exists (ID: ${snap.docs.first.id})');
          continue;
        }

        // Check if we need a new batch
        if (operationsInCurrentBatch >= maxBatchSize) {
          // Commit current batch before creating new one
          await batches[currentBatchIndex].commit();
          debugPrint('FirestoreDatabase: Committed batch ${currentBatchIndex + 1} (had $operationsInCurrentBatch operations)');
          currentBatchIndex++;
          batches.add(firestore.batch());
          operationsInCurrentBatch = 0;
        }

        final docRef = firestore.collection('categories').doc();
        categoryIdByNormName[norm(cat.name)] = docRef.id;
        batches[currentBatchIndex].set(docRef, {
          'name': cat.name,
          'display_order': cat.displayOrder,
          'is_active': 1,
          'is_locked': cat.isLocked ? 1 : 0,
          'created_at': now,
          'updated_at': now,
        });
        operationsInCurrentBatch++;
        categoriesToAdd++;
        debugPrint('FirestoreDatabase: Will create category "${cat.name}" in batch ${currentBatchIndex + 1}');
      }
      
      debugPrint('FirestoreDatabase: Categories processed - ${categoryIdByNormName.length} total, $categoriesToAdd to add, operations in current batch: $operationsInCurrentBatch');

      // Create products (menu items). Inventory is handled separately using
      // purchasable items + purchases, not menu sales.
      int productsAdded = 0;
      int productsSkipped = 0;
      for (final p in chiyagaadiSeedProducts) {
        final categoryId = categoryIdByNormName[norm(p.categoryName)];
        if (categoryId == null) {
          debugPrint('FirestoreDatabase: Skipping product "${p.name}" - category "${p.categoryName}" not found');
          continue;
        }

        final existing = await firestore
            .collection('products')
            .where('name', isEqualTo: p.name)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          productsSkipped++;
          debugPrint('FirestoreDatabase: Product "${p.name}" already exists, skipping');
          continue;
        }

        // Check if we need a new batch
        if (operationsInCurrentBatch >= maxBatchSize) {
          currentBatchIndex++;
          batches.add(firestore.batch());
          operationsInCurrentBatch = 0;
        }

        final productRef = firestore.collection('products').doc();
        batches[currentBatchIndex].set(productRef, {
          'category_id': categoryId,
          'name': p.name,
          'description': p.description,
          'price': p.price,
          'cost': 0.0,
          'image_url': chiyagaadiImageAssetForName(p.name),
          'is_veg': p.isVeg ? 1 : 0,
          'is_active': p.isActive ? 1 : 0,
          'is_purchasable': 0,
          'is_sellable': 1,
          'created_at': now,
          'updated_at': now,
        });
        operationsInCurrentBatch++;
        productsAdded++;
        debugPrint('FirestoreDatabase: Will create product "${p.name}" (Rs ${p.price})');
      }

      // Commit all batches that have operations
      int batchesCommitted = 0;
      
      // Determine how many batches need to be committed
      // If currentBatchIndex is 0 and operationsInCurrentBatch is 0, no batches need committing
      // Otherwise, commit all batches up to currentBatchIndex
      final batchesToCommit = (operationsInCurrentBatch > 0 || currentBatchIndex > 0) ? currentBatchIndex + 1 : 0;
      
      debugPrint('FirestoreDatabase: Committing $batchesToCommit batches (currentBatchIndex: $currentBatchIndex, operationsInCurrentBatch: $operationsInCurrentBatch)...');
      
      if (batchesToCommit > 0) {
        // Commit all batches (including the one we're currently using if it has operations)
        for (int i = 0; i < batchesToCommit; i++) {
          try {
            await batches[i].commit();
            batchesCommitted++;
            debugPrint('FirestoreDatabase: Successfully committed batch ${i + 1}/$batchesToCommit');
          } catch (e) {
            debugPrint('FirestoreDatabase: Error committing batch ${i + 1}: $e');
            rethrow; // Re-throw to show error to user
          }
        }
      } else {
        debugPrint('FirestoreDatabase: No batches to commit (all items may already exist)');
      }
      
      debugPrint('FirestoreDatabase: Chiyagaadi menu seed completed - Added: $productsAdded products, Skipped: $productsSkipped products, Batches committed: $batchesCommitted');
      
      // Wait a moment for Firestore to propagate writes
      // Removed delay for faster operation
      
      // Verify data was saved by querying directly from Firestore
      try {
        final verifyCategories = await firestore.collection('categories').limit(10).get();
        final verifyProducts = await firestore.collection('products').limit(10).get();
        debugPrint('FirestoreDatabase: Verification - Found ${verifyCategories.docs.length} categories and ${verifyProducts.docs.length} products in Firestore');
        
        if (verifyCategories.docs.isNotEmpty) {
          debugPrint('FirestoreDatabase: Sample categories: ${verifyCategories.docs.map((d) => d.data()['name']).join(', ')}');
        }
        if (verifyProducts.docs.isNotEmpty) {
          debugPrint('FirestoreDatabase: Sample products: ${verifyProducts.docs.map((d) => d.data()['name']).join(', ')}');
        }
      } catch (e) {
        debugPrint('FirestoreDatabase: Error verifying saved data: $e');
      }
    } catch (e) {
      debugPrint('FirestoreDatabase: Error seeding menu: $e');
      rethrow; // Re-throw so caller can handle it
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

      // Optimize: support SQL-style `IN (...)` clauses by translating them to Firestore `whereIn`
      // (chunked to respect Firestore limits). This avoids N+1 queries on web.
      if (where != null &&
          whereArgs != null &&
          where.toUpperCase().contains(' IN (') &&
          whereArgs.isNotEmpty) {
        final rows = await _queryWithWhereIn(
          collection: collection,
          where: where,
          whereArgs: whereArgs,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
        );
        return rows;
      }

      Query query = firestore.collection(collection);

      // Apply where clause
      if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
        // Simple where clause parser for common cases
        // Format: "field = ?" or "field1 = ? AND field2 = ?"
        final conditions = where.split(' AND ');
        var argIndex = 0;
        for (var i = 0;
            i < conditions.length && argIndex < whereArgs.length;
            i++) {
          final condition = conditions[i].trim();
          if (condition.contains(' = ?')) {
            final field = condition.split(' = ?')[0].trim();
            query = query.where(field, isEqualTo: whereArgs[argIndex]);
            argIndex++;
          } else if (condition.contains(' != ?')) {
            final field = condition.split(' != ?')[0].trim();
            query = query.where(field, isNotEqualTo: whereArgs[argIndex]);
            argIndex++;
          } else if (condition.contains(' >= ?')) {
            final field = condition.split(' >= ?')[0].trim();
            query =
                query.where(field, isGreaterThanOrEqualTo: whereArgs[argIndex]);
            argIndex++;
          } else if (condition.contains(' <= ?')) {
            final field = condition.split(' <= ?')[0].trim();
            query =
                query.where(field, isLessThanOrEqualTo: whereArgs[argIndex]);
            argIndex++;
          } else if (condition.contains(' > ?')) {
            final field = condition.split(' > ?')[0].trim();
            query = query.where(field, isGreaterThan: whereArgs[argIndex]);
            argIndex++;
          } else if (condition.contains(' < ?')) {
            final field = condition.split(' < ?')[0].trim();
            query = query.where(field, isLessThan: whereArgs[argIndex]);
            argIndex++;
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
        // For IN queries, avoid server-side ordering (often requires composite indexes).
        // We already have a safe chunked implementation + in-memory sorting.
        if (where != null &&
            whereArgs != null &&
            where.toUpperCase().contains(' IN (') &&
            whereArgs.isNotEmpty) {
          return await _queryWithWhereIn(
            collection: collection,
            where: where,
            whereArgs: whereArgs,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
          );
        }

        Query fallbackQuery = firestore.collection(collection);

        // Apply the same where clause (but no orderBy)
        if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
          final conditions = where.split(' AND ');
          var argIndex = 0;
          for (var i = 0;
              i < conditions.length && argIndex < whereArgs.length;
              i++) {
            final condition = conditions[i].trim();
            if (condition.contains(' = ?')) {
              final field = condition.split(' = ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isEqualTo: whereArgs[argIndex]);
              argIndex++;
            } else if (condition.contains(' != ?')) {
              final field = condition.split(' != ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isNotEqualTo: whereArgs[argIndex]);
              argIndex++;
            } else if (condition.contains(' >= ?')) {
              final field = condition.split(' >= ?')[0].trim();
              fallbackQuery = fallbackQuery.where(field,
                  isGreaterThanOrEqualTo: whereArgs[argIndex]);
              argIndex++;
            } else if (condition.contains(' <= ?')) {
              final field = condition.split(' <= ?')[0].trim();
              fallbackQuery = fallbackQuery.where(field,
                  isLessThanOrEqualTo: whereArgs[argIndex]);
              argIndex++;
            } else if (condition.contains(' > ?')) {
              final field = condition.split(' > ?')[0].trim();
              fallbackQuery = fallbackQuery.where(field,
                  isGreaterThan: whereArgs[argIndex]);
              argIndex++;
            } else if (condition.contains(' < ?')) {
              final field = condition.split(' < ?')[0].trim();
              fallbackQuery =
                  fallbackQuery.where(field, isLessThan: whereArgs[argIndex]);
              argIndex++;
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

  Future<List<Map<String, dynamic>>> _queryWithWhereIn({
    required String collection,
    required String where,
    required List<Object?> whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    // Parse conditions: support ONE `IN (...)` plus other simple comparisons joined by AND.
    final conditions = where.split(' AND ').map((s) => s.trim()).toList();
    String? inField;
    List<Object?> inValues = const [];
    final other = <({String field, String op, Object? value})>[];

    var argIndex = 0;
    final inRe = RegExp(r'^(\w+)\s+IN\s*\(([^)]*)\)$', caseSensitive: false);

    for (final cond in conditions) {
      final m = inRe.firstMatch(cond);
      if (m != null) {
        // Count placeholders
        final placeholderCount =
            RegExp(r'\?').allMatches(m.group(2) ?? '').length;
        inField = (m.group(1) ?? '').trim();
        final end = (argIndex + placeholderCount).clamp(0, whereArgs.length);
        inValues = whereArgs.sublist(argIndex, end);
        argIndex = end;
        continue;
      }

      if (cond.contains(' = ?')) {
        final field = cond.split(' = ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add((field: field, op: '=', value: whereArgs[argIndex]));
          argIndex++;
        }
      } else if (cond.contains(' != ?')) {
        final field = cond.split(' != ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add((field: field, op: '!=', value: whereArgs[argIndex]));
          argIndex++;
        }
      } else if (cond.contains(' >= ?')) {
        final field = cond.split(' >= ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add((field: field, op: '>=', value: whereArgs[argIndex]));
          argIndex++;
        }
      } else if (cond.contains(' <= ?')) {
        final field = cond.split(' <= ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add((field: field, op: '<=', value: whereArgs[argIndex]));
          argIndex++;
        }
      } else if (cond.contains(' > ?')) {
        final field = cond.split(' > ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add((field: field, op: '>', value: whereArgs[argIndex]));
          argIndex++;
        }
      } else if (cond.contains(' < ?')) {
        final field = cond.split(' < ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add((field: field, op: '<', value: whereArgs[argIndex]));
          argIndex++;
        }
      }
    }

    if (inField == null || inField.isEmpty || inValues.isEmpty) {
      // Fall back to normal query path if parsing fails.
      return await query(
        collection,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    }

    // Firestore limits whereIn to 10 values.
    final chunks = <List<Object?>>[];
    for (var i = 0; i < inValues.length; i += 10) {
      chunks.add(inValues.sublist(i, (i + 10).clamp(0, inValues.length)));
    }

    Query buildBase() {
      Query q = firestore.collection(collection);
      for (final p in other) {
        if (p.op == '=') {
          q = q.where(p.field, isEqualTo: p.value);
        } else if (p.op == '!=') {
          q = q.where(p.field, isNotEqualTo: p.value);
        } else if (p.op == '>=') {
          q = q.where(p.field, isGreaterThanOrEqualTo: p.value);
        } else if (p.op == '<=') {
          q = q.where(p.field, isLessThanOrEqualTo: p.value);
        } else if (p.op == '>') {
          q = q.where(p.field, isGreaterThan: p.value);
        } else if (p.op == '<') {
          q = q.where(p.field, isLessThan: p.value);
        }
      }
      return q;
    }

    Future<List<QueryDocumentSnapshot>> runChunk(List<Object?> vals) async {
      Query q = buildBase();
      final isDocIdField = inField == 'id' ||
          inField == 'documentId' ||
          inField == 'document_id';
      if (isDocIdField) {
        q = q.where(FieldPath.documentId, whereIn: vals);
      } else if (inField != null && inField.isNotEmpty) {
        q = q.where(inField, whereIn: vals);
      } else {
        throw ArgumentError('Invalid inField for whereIn query');
      }

      // Avoid applying orderBy server-side here to reduce index requirements;
      // sort in-memory below if requested.
      final snap = await q.get();
      return snap.docs;
    }

    final docsById = <String, Map<String, dynamic>>{};
    final docLists = await Future.wait(chunks.map(runChunk));
    for (final docs in docLists) {
      for (final doc in docs) {
        final data = (doc.data() as Map<String, dynamic>);
        data['id'] = doc.id;
        docsById[doc.id] = data;
      }
    }

    final rows = docsById.values.toList();
    if (orderBy != null) {
      _sortRowsInMemory(rows, orderBy);
    }

    // Apply offset/limit in-memory
    final start = (offset ?? 0).clamp(0, rows.length);
    final sliced = rows.skip(start);
    if (limit != null) {
      return sliced.take(limit).toList();
    }
    return sliced.toList();
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

  Future<String> insert(String collection, Map<String, dynamic> data, {String? documentId}) async {
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

      DocumentReference docRef;
      if (documentId != null && documentId.isNotEmpty) {
        // Use specific document ID
        docRef = firestore.collection(collection).doc(documentId);
        await docRef.set(dataToInsert);
        debugPrint(
            'FirestoreDatabase: Inserted document $documentId into $collection with specific ID');
      } else {
        // Auto-generate document ID
        docRef = await firestore.collection(collection).add(dataToInsert);
        debugPrint(
            'FirestoreDatabase: Inserted document ${docRef.id} into $collection');
      }
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

  /// Clears only order-section data (orders, order_items, payments).
  /// Keeps products, inventory, customers, and all other business data.
  Future<void> clearOrdersData() async {
    if (!_isInitialized) {
      await init();
    }
    final orderCollections = <String>['order_items', 'payments', 'orders'];
    int totalDeleted = 0;
    for (final name in orderCollections) {
      totalDeleted += await _deleteCollectionInBatches(name);
    }
    debugPrint(
        'FirestoreDatabase: Cleared orders data. Deleted $totalDeleted documents');
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

    debugPrint(
        'FirestoreDatabase: Cleared business data. Deleted $totalDeleted documents');

    if (seedDefaults) {
      // Re-seed settings + menu.
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
