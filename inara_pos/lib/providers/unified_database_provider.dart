import 'package:flutter/foundation.dart'
    show kIsWeb, ChangeNotifier, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'database_provider.dart';
import 'firestore_database_provider.dart';
import '../firebase_options.dart';

/// Unified database provider that uses SQLite on mobile and Firestore on web
class UnifiedDatabaseProvider with ChangeNotifier {
  late final dynamic _provider;
  bool _isInitialized = false;
  bool _initFailed = false; // Track if initialization failed

  UnifiedDatabaseProvider() {
    if (kIsWeb) {
      _provider = FirestoreDatabaseProvider();
      debugPrint('UnifiedDatabase: Using Firestore for web');
    } else {
      _provider = DatabaseProvider();
      debugPrint('UnifiedDatabase: Using SQLite for mobile');
    }
  }

  /// Force re-initialization (resets failure flag)
  Future<void> forceInit() async {
    debugPrint('UnifiedDatabase: Force re-initialization requested');
    _initFailed = false;
    _isInitialized = false;
    await init();
  }

  Future<void> init({bool forceRetry = false}) async {
    if (_isInitialized && !forceRetry) {
      return;
    }
    
    // If init already failed, don't retry automatically (prevents infinite loops)
    // But allow retry if forceRetry is true
    if (_initFailed && !forceRetry) {
      debugPrint('UnifiedDatabase: Init previously failed, skipping retry (use forceInit() to retry)');
      return;
    }
    
    // Reset failure flag if we're retrying
    if (forceRetry) {
      _initFailed = false;
      _isInitialized = false;
      debugPrint('UnifiedDatabase: Retrying initialization...');
    }

    try {
      // Ensure Firebase is initialized before any Firestore access (web).
      if (kIsWeb) {
        try {
          if (Firebase.apps.isEmpty) {
            try {
              FirebaseOptions? options;
              try {
                options = DefaultFirebaseOptions.currentPlatform;
              } catch (e) {
                debugPrint('UnifiedDatabase: Error getting Firebase options: $e');
                // Fallback: try to use web options directly
                try {
                  options = DefaultFirebaseOptions.web;
                  debugPrint('UnifiedDatabase: Using web Firebase options as fallback');
                } catch (fallbackError) {
                  debugPrint('UnifiedDatabase: Fallback also failed: $fallbackError');
                  throw StateError('Failed to get Firebase options: $e');
                }
              }
              
              if (options == null) {
                throw StateError('Firebase options is null');
              }
              
              await Firebase.initializeApp(options: options);
              debugPrint('UnifiedDatabase: Firebase initialized (web)');
              
              // iOS Safari: Wait a bit longer to ensure Firebase is fully ready
              if (defaultTargetPlatform == TargetPlatform.iOS) {
                await Future.delayed(const Duration(milliseconds: 300));
                debugPrint('UnifiedDatabase: iOS Safari delay applied');
              }
            } catch (initError) {
              debugPrint('UnifiedDatabase: Failed to initialize Firebase: $initError');
              throw StateError('Failed to initialize Firebase: $initError');
            }
          } else {
            debugPrint('UnifiedDatabase: Firebase already initialized');
          }
          
          // Additional delay for iOS Safari before accessing Firestore
          if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
            await Future.delayed(const Duration(milliseconds: 200));
          }

          // IMPORTANT: Sign in with Firebase Auth using admin email/password
          // This satisfies Firestore rules that require `request.auth != null`
          // Admin credentials: chiyagadi@gmail.com / Chiyagadi15@
          // NOTE: We wrap this in try-catch to avoid minified JS type errors
          try {
            // Defensive access to FirebaseAuth - avoid type checking in minified JS
            dynamic authInstance;
            try {
              authInstance = FirebaseAuth.instance;
            } catch (e) {
              debugPrint('UnifiedDatabase: Error getting FirebaseAuth.instance: $e');
              // Continue without auth - Firestore may still work if rules are public
              debugPrint('UnifiedDatabase: Continuing without Firebase Auth');
            }
            
            if (authInstance != null) {
              // Check if already signed in - use defensive access
              dynamic currentUser;
              try {
                currentUser = authInstance.currentUser;
              } catch (e) {
                debugPrint('UnifiedDatabase: Error checking Firebase Auth: $e');
                // If checking currentUser fails, try to sign in anyway
                currentUser = null;
              }
              
              if (currentUser == null) {
                // Sign in with admin Firebase Auth credentials
                try {
                  await authInstance.signInWithEmailAndPassword(
                    email: 'chiyagadi@gmail.com',
                    password: 'Chiyagadi15@',
                  );
                  debugPrint('UnifiedDatabase: Firebase Auth email/password sign-in ok');
                } catch (signInError) {
                  debugPrint('UnifiedDatabase: Firebase Auth sign-in failed: $signInError');
                  // If email/password auth fails, try to continue (rules may be public)
                  // But log the error for debugging
                  final errorMsg = signInError.toString();
                  if (errorMsg.contains('user-not-found') || 
                      errorMsg.contains('wrong-password') ||
                      errorMsg.contains('invalid-email')) {
                    debugPrint('UnifiedDatabase: Admin Firebase Auth user not found or invalid credentials');
                    debugPrint('UnifiedDatabase: Please ensure admin user exists in Firebase Console');
                  }
                  // Continue - Firestore may still work if rules are public
                  debugPrint('UnifiedDatabase: Continuing without Firebase Auth (rules may be public)');
                }
              } else {
                try {
                  final email = currentUser.email;
                  debugPrint('UnifiedDatabase: Firebase Auth already signed in as $email');
                } catch (e) {
                  debugPrint('UnifiedDatabase: Firebase Auth already signed in (could not get email)');
                }
              }
            }
          } catch (authError) {
            debugPrint('UnifiedDatabase: Firebase Auth error: $authError');
            // Continue - Firestore may still work if rules are public
            debugPrint('UnifiedDatabase: Continuing without Firebase Auth (rules may be public)');
          }
        } catch (e) {
          final errorMsg = e.toString();
          debugPrint('UnifiedDatabase: Firebase init error (web): $e');
          
          // Don't fail initialization if it's just a Firebase Auth error
          // Firestore may still work even if Auth fails
          if (errorMsg.contains('Firebase Auth') || 
              errorMsg.contains('minified') ||
              errorMsg.contains('TypeError')) {
            debugPrint('UnifiedDatabase: Firebase Auth error detected, continuing with Firestore init');
            // Continue - don't rethrow Auth errors
          } else {
            // For other errors (like Firebase initialization failures), still rethrow
            debugPrint('UnifiedDatabase: Critical Firebase error, rethrowing');
            rethrow;
          }
        }
      }

      // Try to initialize the provider (Firestore or SQLite)
      // Wrap in try-catch to handle any errors gracefully
      try {
        await _provider.init();
        _isInitialized = true;
        _initFailed = false; // Reset failure flag on success
        debugPrint('UnifiedDatabase: Initialized successfully');
      } catch (providerError) {
        final providerErrorMsg = providerError.toString();
        debugPrint('UnifiedDatabase: Provider init failed: $providerError');
        
        // If it's a null check error or minified JS error, it might be transient
        // Don't mark as permanently failed - allow retries via forceInit()
        if (providerErrorMsg.contains('Null check operator') || 
            providerErrorMsg.contains('null value') ||
            providerErrorMsg.contains('minified') ||
            providerErrorMsg.contains('TypeError')) {
          debugPrint('UnifiedDatabase: Transient error in provider init (null check/minified JS)');
          debugPrint('UnifiedDatabase: This is often caused by:');
          debugPrint('UnifiedDatabase: 1. Firebase not fully initialized on iOS Safari');
          debugPrint('UnifiedDatabase: 2. Firestore instance not available');
          debugPrint('UnifiedDatabase: 3. Browser compatibility issue');
          debugPrint('UnifiedDatabase: Will allow retries for this error (use forceInit())');
          
          // For transient errors, mark as failed but allow retries via forceInit()
          _initFailed = true;
          _isInitialized = false;
          // Don't rethrow - allow app to continue
        } else {
          // For other errors, mark as failed
          _initFailed = true;
          _isInitialized = false;
          debugPrint('UnifiedDatabase: Provider initialization failed: $providerError');
          // Don't rethrow - allow app to continue
        }
      }
    } catch (e) {
      debugPrint('UnifiedDatabase: Initialization failed: $e');
      final errorMsg = e.toString();
      
      // Mark as failed but don't throw - allow app to continue
      _initFailed = true;
      _isInitialized = false;
      
      // Log helpful information
      if (errorMsg.contains('Null check operator') || errorMsg.contains('null value')) {
        debugPrint('UnifiedDatabase: Null check error detected.');
        debugPrint('UnifiedDatabase: This is often caused by:');
        debugPrint('UnifiedDatabase: 1. Firebase not fully initialized on iOS Safari');
        debugPrint('UnifiedDatabase: 2. Firestore instance not available');
        debugPrint('UnifiedDatabase: 3. Browser compatibility issue');
        debugPrint('UnifiedDatabase: App will continue but database operations may fail.');
        debugPrint('UnifiedDatabase: Use forceInit() to retry initialization.');
      }
      
      // Don't rethrow - allow app to continue even if database init fails
      // Screens should handle empty results gracefully
    }
  }
  
  /// Check if database is available
  bool get isAvailable => _isInitialized && !_initFailed;

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
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, return empty list instead of throwing
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Query skipped - database not available');
      return [];
    }
    
    try {
      return await _provider.query(
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
    } catch (e) {
      debugPrint('UnifiedDatabase: Query error: $e');
      return []; // Return empty list on error
    }
  }

  Future<dynamic> insert(String table, Map<String, dynamic> values, {String? documentId}) async {
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, return null instead of throwing
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Insert skipped - database not available');
      return null;
    }

    try {
      if (kIsWeb) {
        // Firestore returns String (document ID)
        return await _provider.insert(table, values, documentId: documentId);
      } else {
        // SQLite returns int (documentId parameter ignored on SQLite)
        return await _provider.insert(table, values);
      }
    } catch (e) {
      debugPrint('UnifiedDatabase: Insert error: $e');
      return null; // Return null on error
    }
  }

  Future<int> update(
    String table, {
    required Map<String, dynamic> values,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, return 0 instead of throwing
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Update skipped - database not available');
      return 0;
    }
    
    try {
      if (kIsWeb) {
        // FirestoreDatabaseProvider.update expects `data: ...`
        return await _provider.update(
          table,
          data: values,
          where: where,
          whereArgs: whereArgs,
        );
      }

      // DatabaseProvider.update (SQLite) expects the values map as the 2nd positional argument.
      return await _provider.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e) {
      debugPrint('UnifiedDatabase: Update error: $e');
      return 0; // Return 0 on error (no rows updated)
    }
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, return 0 instead of throwing
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Delete skipped - database not available');
      return 0;
    }
    
    try {
      return await _provider.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    } catch (e) {
      debugPrint('UnifiedDatabase: Delete error: $e');
      return 0; // Return 0 on error (no rows deleted)
    }
  }

  Future<T?> transaction<T>(Future<T> Function(dynamic txn) action) async {
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, return null instead of throwing
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Transaction skipped - database not available');
      return null;
    }
    
    try {
      return await _provider.transaction(action);
    } catch (e) {
      debugPrint('UnifiedDatabase: Transaction error: $e');
      return null; // Return null on error
    }
  }

  Future<void> resetDatabase() async {
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, just return (nothing to reset)
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Reset skipped - database not available');
      return;
    }
    
    try {
      return await _provider.resetDatabase();
    } catch (e) {
      debugPrint('UnifiedDatabase: Reset error: $e');
      // Don't throw - just log the error
    }
  }

  /// Clears business data created/entered through the app while keeping
  /// authentication/users and settings intact.
  ///
  /// On SQLite (mobile), this also optionally reseeds default categories/products.
  /// On Firestore (web), deletion is performed in safe batches.
  Future<void> clearBusinessData({bool seedDefaults = true}) async {
    if (!_isInitialized) {
      await init();
    }
    
    // If init failed, just return (nothing to clear)
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Clear business data skipped - database not available');
      return;
    }
    
    try {
      return await _provider.clearBusinessData(seedDefaults: seedDefaults);
    } catch (e) {
      debugPrint('UnifiedDatabase: Clear business data error: $e');
      // Don't throw - just log the error
    }
  }

  Future<void> close() async {
    if (_isInitialized) {
      await _provider.close();
    }
  }
  
  /// Manually seed menu items from chiyagaadi_menu_seed.dart
  /// This will add all categories and products to Firestore
  Future<bool> seedMenuItems() async {
    try {
      // Ensure database is initialized
      if (!_isInitialized) {
        await init();
      }
      
      // If database is not available, try to force reinitialize
      if (!isAvailable) {
        debugPrint('UnifiedDatabase: Database not available, attempting to force reinitialize...');
        await forceInit();
        
        if (!isAvailable) {
          debugPrint('UnifiedDatabase: Cannot seed menu - database still not available after retry');
          return false;
        }
      }
      
      // Call the seed function on the provider
      if (kIsWeb) {
        // For web, use FirestoreDatabaseProvider
        if (_provider is FirestoreDatabaseProvider) {
          final firestoreProvider = _provider as FirestoreDatabaseProvider;
          await firestoreProvider.seedMenuItems();
          debugPrint('UnifiedDatabase: Menu items seeded successfully to Firestore');
          return true;
        } else {
          debugPrint('UnifiedDatabase: Provider is not FirestoreDatabaseProvider on web');
          return false;
        }
      } else {
        // For SQLite, the seed happens during init
        // But we can trigger it manually by calling clearBusinessData with seedDefaults=true
        await clearBusinessData(seedDefaults: true);
        debugPrint('UnifiedDatabase: Menu items seeded successfully (SQLite)');
        return true;
      }
    } catch (e) {
      debugPrint('UnifiedDatabase: Error seeding menu items: $e');
      return false;
    }
  }
}
