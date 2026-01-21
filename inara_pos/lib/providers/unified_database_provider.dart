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

  UnifiedDatabaseProvider() {
    if (kIsWeb) {
      _provider = FirestoreDatabaseProvider();
      debugPrint('UnifiedDatabase: Using Firestore for web');
    } else {
      _provider = DatabaseProvider();
      debugPrint('UnifiedDatabase: Using SQLite for mobile');
    }
  }

  Future<void> init() async {
    if (_isInitialized) {
      return;
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

      await _provider.init();
      _isInitialized = true;
      debugPrint('UnifiedDatabase: Initialized successfully');
    } catch (e) {
      debugPrint('UnifiedDatabase: Initialization failed: $e');
      final errorMsg = e.toString();
      
      // Provide more helpful error message for null check errors
      if (errorMsg.contains('Null check operator') || errorMsg.contains('null value')) {
        throw StateError(
          'Database initialization failed: Null check error detected.\n\n'
          'This is often caused by:\n'
          '1. Firebase not fully initialized on iOS Safari\n'
          '2. Firestore instance not available\n'
          '3. Browser compatibility issue\n\n'
          'Try:\n'
          '1. Hard refresh the page (Cmd+Shift+R on Mac)\n'
          '2. Clear browser cache\n'
          '3. Check browser console (F12) for details\n\n'
          'Original error: $e'
        );
      }
      
      rethrow;
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
  }

  Future<dynamic> insert(String table, Map<String, dynamic> values, {String? documentId}) async {
    if (!_isInitialized) {
      await init();
    }

    if (kIsWeb) {
      // Firestore returns String (document ID)
      return await _provider.insert(table, values, documentId: documentId);
    } else {
      // SQLite returns int (documentId parameter ignored on SQLite)
      return await _provider.insert(table, values);
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
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!_isInitialized) {
      await init();
    }
    return await _provider.delete(
      table,
      where: where,
      whereArgs: whereArgs,
    );
  }

  Future<T?> transaction<T>(Future<T> Function(dynamic txn) action) async {
    if (!_isInitialized) {
      await init();
    }
    return await _provider.transaction(action);
  }

  Future<void> resetDatabase() async {
    if (!_isInitialized) {
      await init();
    }
    return await _provider.resetDatabase();
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
    return await _provider.clearBusinessData(seedDefaults: seedDefaults);
  }

  Future<void> close() async {
    if (_isInitialized) {
      await _provider.close();
    }
  }
}
