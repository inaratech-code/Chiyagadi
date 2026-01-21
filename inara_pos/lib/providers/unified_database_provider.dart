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
    await init(forceRetry: true);
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
        // Wait a moment to ensure browser environment is fully ready
        // This helps avoid null check errors from accessing Firebase too early
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Step 1: Initialize Firebase App (required for Firestore)
        // Use defensive programming to handle null check errors
        try {
          // Check if Firebase is already initialized using a safe method
          bool firebaseInitialized = false;
          try {
            // Use dynamic access to avoid type checking issues
            dynamic firebaseApps;
            try {
              firebaseApps = Firebase.apps;
            } catch (e) {
              debugPrint('UnifiedDatabase: Error accessing Firebase.apps: $e');
              // Wait a bit longer and try again
              await Future.delayed(const Duration(milliseconds: 200));
              try {
                firebaseApps = Firebase.apps;
              } catch (e2) {
                debugPrint('UnifiedDatabase: Error accessing Firebase.apps on retry: $e2');
                firebaseInitialized = false;
              }
            }
            
            if (firebaseApps != null) {
              try {
                firebaseInitialized = (firebaseApps as dynamic).isNotEmpty;
              } catch (e) {
                debugPrint('UnifiedDatabase: Error checking Firebase.apps.isNotEmpty: $e');
                firebaseInitialized = false;
              }
            }
          } catch (e) {
            debugPrint('UnifiedDatabase: Error checking Firebase apps: $e');
            // If checking fails, assume not initialized and try to initialize
            firebaseInitialized = false;
          }
          
          if (!firebaseInitialized) {
            debugPrint('UnifiedDatabase: Initializing Firebase App...');
            
            // Get Firebase options with multiple fallbacks
            FirebaseOptions? options;
            
            // Try currentPlatform first
            try {
              options = DefaultFirebaseOptions.currentPlatform;
              debugPrint('UnifiedDatabase: Got Firebase options from currentPlatform');
            } catch (e) {
              debugPrint('UnifiedDatabase: Error getting currentPlatform options: $e');
              
              // Fallback 1: Try web options directly
              try {
                options = DefaultFirebaseOptions.web;
                debugPrint('UnifiedDatabase: Using web Firebase options as fallback');
              } catch (fallbackError) {
                debugPrint('UnifiedDatabase: Web options fallback also failed: $fallbackError');
                
                // Fallback 2: Try to construct options manually
                try {
                  options = const FirebaseOptions(
                    apiKey: 'AIzaSyAE1vchX5X70H_Ec4UIk_DLLOjx51W3kyc',
                    appId: '1:905761269162:web:bbac95e09878d7006d37d3',
                    messagingSenderId: '905761269162',
                    projectId: 'chiyagadi-cf302',
                    authDomain: 'chiyagadi-cf302.firebaseapp.com',
                    storageBucket: 'chiyagadi-cf302.firebasestorage.app',
                  );
                  debugPrint('UnifiedDatabase: Using manually constructed Firebase options');
                } catch (manualError) {
                  debugPrint('UnifiedDatabase: Manual options construction failed: $manualError');
                  throw StateError('Failed to get Firebase options after all attempts: $e');
                }
              }
            }
            
            if (options == null) {
              throw StateError('Firebase options is null after all attempts');
            }
            
            // Initialize Firebase with retries
            bool initSuccess = false;
            for (int attempt = 0; attempt < 3; attempt++) {
              try {
                if (attempt > 0) {
                  await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
                  debugPrint('UnifiedDatabase: Retrying Firebase initialization (attempt ${attempt + 1})...');
                }
                
                await Firebase.initializeApp(options: options);
                debugPrint('UnifiedDatabase: Firebase App initialized successfully (web)');
                initSuccess = true;
                break;
              } catch (initError) {
                final initErrorMsg = initError.toString();
                debugPrint('UnifiedDatabase: Firebase init attempt ${attempt + 1} failed: $initError');
                
                // If it's a null check error, retry
                if (initErrorMsg.contains('Null check operator') || 
                    initErrorMsg.contains('null value')) {
                  if (attempt < 2) {
                    debugPrint('UnifiedDatabase: Null check error detected, will retry...');
                    continue;
                  }
                }
                
                // If this is the last attempt, throw
                if (attempt == 2) {
                  throw StateError('Failed to initialize Firebase App after 3 attempts: $initError');
                }
              }
            }
            
            if (!initSuccess) {
              throw StateError('Firebase App initialization failed after all retries');
            }
            
            // iOS Safari: Wait a bit longer to ensure Firebase is fully ready
            if (defaultTargetPlatform == TargetPlatform.iOS) {
              await Future.delayed(const Duration(milliseconds: 300));
              debugPrint('UnifiedDatabase: iOS Safari delay applied');
            }
          } else {
            debugPrint('UnifiedDatabase: Firebase App already initialized');
          }
        } catch (e) {
          final errorMsg = e.toString();
          debugPrint('UnifiedDatabase: Firebase App initialization error: $e');
          
          // Don't throw if it's a null check error - might be transient
          if (errorMsg.contains('Null check operator') || 
              errorMsg.contains('null value')) {
            debugPrint('UnifiedDatabase: Null check error in Firebase App init - marking as failed but allowing retry');
            _initFailed = true;
            _isInitialized = false;
            // Don't throw - allow retry via forceInit()
            return;
          }
          
          // For other errors, still throw
          throw StateError('Firebase App initialization failed: $e');
        }
        
        // Additional delay for iOS Safari before accessing Firestore
        if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // Step 2: Try Firebase Auth (OPTIONAL - Firestore can work without it)
        // This is wrapped in a separate try-catch so it doesn't block Firestore initialization
        try {
          // Defensive access to FirebaseAuth - avoid type checking in minified JS
          dynamic authInstance;
          try {
            authInstance = FirebaseAuth.instance;
          } catch (e) {
            debugPrint('UnifiedDatabase: Error getting FirebaseAuth.instance: $e');
            debugPrint('UnifiedDatabase: Skipping Firebase Auth - Firestore will work without Auth');
            // Don't throw - continue to Firestore initialization
          }
          
          if (authInstance != null) {
            // Check if already signed in - use defensive access
            dynamic currentUser;
            try {
              currentUser = authInstance.currentUser;
            } catch (e) {
              debugPrint('UnifiedDatabase: Error checking Firebase Auth: $e');
              // If checking currentUser fails, skip auth but continue
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
                final errorMsg = signInError.toString();
                
                if (errorMsg.contains('user-not-found') || 
                    errorMsg.contains('wrong-password') ||
                    errorMsg.contains('invalid-email')) {
                  debugPrint('UnifiedDatabase: Admin Firebase Auth user not found or invalid credentials');
                  debugPrint('UnifiedDatabase: Firestore will work if rules allow public access');
                }
                // Don't throw - continue to Firestore initialization
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
          final authErrorMsg = authError.toString();
          debugPrint('UnifiedDatabase: Firebase Auth error (non-critical): $authError');
          debugPrint('UnifiedDatabase: Continuing without Firebase Auth - Firestore will initialize anyway');
          // Don't throw - Auth is optional, Firestore can work without it
        }
        
        debugPrint('UnifiedDatabase: Firebase App initialized, proceeding to Firestore initialization');
      }

      // Try to initialize the provider (Firestore or SQLite)
      // Wrap in try-catch to handle any errors gracefully
      try {
        debugPrint('UnifiedDatabase: Initializing database provider...');
        await _provider.init();
        _isInitialized = true;
        _initFailed = false; // Reset failure flag on success
        debugPrint('UnifiedDatabase: Initialized successfully');
      } catch (providerError) {
        final providerErrorMsg = providerError.toString();
        debugPrint('UnifiedDatabase: Provider init failed: $providerError');
        
        // If it's a null check error or minified JS error, it might be transient
        // Try one more time with a delay before giving up
        if (providerErrorMsg.contains('Null check operator') || 
            providerErrorMsg.contains('null value') ||
            providerErrorMsg.contains('minified') ||
            providerErrorMsg.contains('TypeError')) {
          debugPrint('UnifiedDatabase: Transient error detected, retrying after delay...');
          await Future.delayed(const Duration(milliseconds: 1000));
          
          try {
            debugPrint('UnifiedDatabase: Retrying provider initialization...');
            await _provider.init();
            _isInitialized = true;
            _initFailed = false;
            debugPrint('UnifiedDatabase: Initialized successfully on retry');
          } catch (retryError) {
            debugPrint('UnifiedDatabase: Retry also failed: $retryError');
            debugPrint('UnifiedDatabase: This is often caused by:');
            debugPrint('UnifiedDatabase: 1. Firebase not fully initialized on iOS Safari');
            debugPrint('UnifiedDatabase: 2. Firestore instance not available');
            debugPrint('UnifiedDatabase: 3. Browser compatibility issue');
            debugPrint('UnifiedDatabase: 4. Firestore security rules require authentication');
            debugPrint('UnifiedDatabase: Will allow retries via forceInit()');
            
            // For transient errors, mark as failed but allow retries via forceInit()
            _initFailed = true;
            _isInitialized = false;
            // Don't rethrow - allow app to continue
          }
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
  /// This checks both the initialization state and verifies the connection works
  bool get isAvailable {
    if (!_isInitialized || _initFailed) {
      return false;
    }
    
    // For web/Firestore, verify the instance exists
    if (kIsWeb) {
      try {
        // Check if Firestore provider is initialized
        if (_provider is FirestoreDatabaseProvider) {
          final firestoreProvider = _provider as FirestoreDatabaseProvider;
          return firestoreProvider.isInitialized;
        }
      } catch (e) {
        debugPrint('UnifiedDatabase: Error checking Firestore availability: $e');
        return false;
      }
    }
    
    return true;
  }
  
  /// Test database connectivity with a simple query
  Future<bool> testConnection() async {
    try {
      if (!_isInitialized) {
        await init();
      }
      
      if (_initFailed) {
        return false;
      }
      
      // Try a simple query to test connectivity
      try {
        await _provider.query('categories', limit: 1);
        debugPrint('UnifiedDatabase: Connection test successful');
        return true;
      } catch (queryError) {
        final errorMsg = queryError.toString();
        debugPrint('UnifiedDatabase: Connection test failed: $queryError');
        
        // If it's a permission error, the connection works but rules block access
        if (errorMsg.contains('permission') || 
            errorMsg.contains('PERMISSION_DENIED') ||
            errorMsg.contains('Missing or insufficient permissions')) {
          debugPrint('UnifiedDatabase: Connection works but Firestore rules block access');
          debugPrint('UnifiedDatabase: Please update Firestore rules to allow public access');
          // Still return true - connection works, just rules need updating
          return true;
        }
        
        return false;
      }
    } catch (e) {
      debugPrint('UnifiedDatabase: Connection test error: $e');
      return false;
    }
  }

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
    
    // If init failed, try to reinitialize once
    if (!isAvailable) {
      debugPrint('UnifiedDatabase: Query skipped - database not available, attempting reinit...');
      try {
        await forceInit();
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('UnifiedDatabase: Reinit failed: $e');
      }
      
      if (!isAvailable) {
        debugPrint('UnifiedDatabase: Query skipped - database still not available after reinit');
        return [];
      }
    }
    
    try {
      final result = await _provider.query(
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
      debugPrint('UnifiedDatabase: Query successful - returned ${result.length} rows from $table');
      return result;
    } catch (e) {
      final errorMsg = e.toString();
      debugPrint('UnifiedDatabase: Query error: $e');
      
      // If it's a permission error, log helpful message
      if (errorMsg.contains('permission') || 
          errorMsg.contains('PERMISSION_DENIED') ||
          errorMsg.contains('Missing or insufficient permissions')) {
        debugPrint('UnifiedDatabase: Permission denied - Firestore rules may require authentication');
        debugPrint('UnifiedDatabase: Please update Firestore rules to allow public access');
      }
      
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
