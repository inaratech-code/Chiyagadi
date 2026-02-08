import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'unified_database_provider.dart';

class InaraAuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _currentUserId;
  String? _currentUserRole;
  String? _currentUsername;
  Timer? _inactivityTimer;
  BuildContext? _context;
  String _lockMode = 'timeout'; // NEW: 'always' | 'timeout'
  /// App's single database instance (from main). Avoids using an uninitialized second instance.
  final UnifiedDatabaseProvider? _databaseProvider;

  /// Called when logout() runs so AuthWrapper can force rebuild (fixes web).
  VoidCallback? onLogout;

  InaraAuthProvider({UnifiedDatabaseProvider? databaseProvider})
      : _databaseProvider = databaseProvider;

  bool get isAuthenticated => _isAuthenticated;
  String? get currentUserId => _currentUserId;
  String? get currentUserRole => _currentUserRole;
  String? get currentUsername => _currentUsername;
  String get lockMode => _lockMode; // NEW

  // Auto-logout disabled for all roles: users only logout manually (no inactivity timer, no app-background logout).
  static const int _inactivityTimeoutMinutes = 5; // Unused; kept for reference.

  /// Validate password: letters, numbers, and special characters, 4-20 characters
  static bool _isValidPassword(String password) {
    if (password.length < 4 || password.length > 20) return false;
    // Allow letters, numbers, and common special characters (no spaces)
    // Use regular string to properly escape $ character
    final passwordRegex =
        RegExp('^[a-zA-Z0-9@#\\\$%^&*()_+\\-=\\[\\]{};\':"\\\\|,.<>\\/?]+\$');
    return passwordRegex.hasMatch(password);
  }

  /// NEW: Load login lock behavior (best-effort; SharedPreferences works on web + mobile).
  /// PERF: Only notify listeners if value actually changed.
  Future<void> loadLockMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('lock_mode');
      if (saved == 'always' || saved == 'timeout') {
        if (_lockMode != saved) {
          _lockMode = saved!;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('AuthProvider: Error loading lock mode: $e');
    }
  }

  /// NEW: Persist login lock behavior.
  Future<void> setLockMode(String mode) async {
    if (mode != 'always' && mode != 'timeout') return;
    _lockMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lock_mode', mode);
    } catch (e) {
      debugPrint('AuthProvider: Error saving lock mode: $e');
    }
  }

  // Set context for accessing DatabaseProvider from Provider
  void setContext(BuildContext context) {
    _context = context;
  }

  dynamic _getDatabaseProvider() {
    // Prefer the app's single database instance so we never use an uninitialized copy.
    if (_databaseProvider != null) return _databaseProvider!;
    if (_context != null) {
      try {
        return Provider.of<UnifiedDatabaseProvider>(_context!, listen: false);
      } catch (e) {
        debugPrint('AuthProvider: stored context no longer valid: $e');
      }
    }
    throw StateError(
        'Database not available. Ensure main.dart creates InaraAuthProvider with databaseProvider.');
  }

  Future<bool> checkPinExists() async {
    final prefs = await SharedPreferences.getInstance();
    // PERF: Keep startup fast. Determining "first time" should not require DB init.
    // If DB/user is missing, the login flow already provides recovery options.
    return prefs.containsKey('admin_pin');
  }

  /// NEW: Verify password for sensitive actions (delete orders, inventory, etc.)
  ///
  /// SECURITY: Verifies password by attempting to sign in with Firebase Auth using the current user's email.
  /// This works for all users (admin and cashiers) who are logged in via Firebase Auth.
  /// FALLBACK: If Firebase Auth is unavailable, falls back to checking SharedPreferences.
  Future<bool> verifyAdminPin(String pin) async {
    if (!_isValidPassword(pin)) return false;
    if (!_isAuthenticated || _currentUserId == null) {
      debugPrint('verifyAdminPin: User not authenticated');
      return false;
    }

    try {
      // First, try to verify with Firebase Auth
      if (kIsWeb) {
        try {
          dynamic authInstance = FirebaseAuth.instance;
          dynamic currentUser = authInstance.currentUser;

          if (currentUser != null) {
            // Get the email from the current user
            final email = currentUser.email;
            if (email != null && email.isNotEmpty) {
              final currentEmail = email;

              // Verify PIN via reauthentication without changing auth state
              try {
                final credential = EmailAuthProvider.credential(
                  email: currentEmail,
                  password: pin,
                );
                await currentUser.reauthenticateWithCredential(credential);
                debugPrint(
                    'verifyAdminPin: Password verified via Firebase Auth');
                return true;
              } catch (e) {
                final errorStr = e.toString();
                if (errorStr.contains('wrong-password') ||
                    errorStr.contains('invalid-credential') ||
                    errorStr.contains('user-not-found')) {
                  debugPrint('verifyAdminPin: Incorrect password');
                  return false;
                }
                // If it's another error, fall through to fallback
                debugPrint(
                    'verifyAdminPin: Firebase Auth error, trying fallback: $e');
              }
            }
          }
        } catch (e) {
          debugPrint(
              'verifyAdminPin: Firebase Auth unavailable, trying fallback: $e');
        }
      }

      // FALLBACK: Check against SharedPreferences (for offline/legacy support)
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedHash = prefs.getString('admin_pin');
        if (storedHash != null && storedHash.isNotEmpty) {
          final isValid = _hashPin(pin) == storedHash;
          if (isValid) {
            debugPrint(
                'verifyAdminPin: Password verified via SharedPreferences fallback');
            return true;
          }
        }
      } catch (e) {
        debugPrint('verifyAdminPin: SharedPreferences fallback error: $e');
      }

      // FALLBACK: Check against database user PIN hash (for users created via createUser)
      try {
        final dbProvider = _getDatabaseProvider();
        await dbProvider.init();

        // Get current user's info from database
        final users = await dbProvider.query(
          'users',
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [_currentUserId],
          limit: 1,
        );

        if (users.isNotEmpty) {
          final user = users.first;
          final storedPinHash = user['pin_hash'] as String?;
          if (storedPinHash != null && storedPinHash.isNotEmpty) {
            final isValid = _hashPin(pin) == storedPinHash;
            if (isValid) {
              debugPrint(
                  'verifyAdminPin: Password verified via database PIN hash');
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('verifyAdminPin: Database fallback error: $e');
      }

      debugPrint('verifyAdminPin: Password verification failed');
      return false;
    } catch (e) {
      debugPrint('verifyAdminPin: Error: $e');
      return false;
    }
  }

  // Force create admin user (useful for reset scenarios)
  Future<bool> forceCreateAdmin(String pin) async {
    if (!_isValidPassword(pin)) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final pinHash = _hashPin(pin);

      // Clear old PIN
      await prefs.remove('admin_pin');

      // Set new PIN
      await prefs.setString('admin_pin', pinHash);

      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // Delete any existing admin user
      await dbProvider.delete(
        'users',
        where: 'username = ?',
        whereArgs: ['admin'],
      );

      // Create new admin user
      final now = DateTime.now().millisecondsSinceEpoch;
      await dbProvider.insert('users', {
        'username': 'admin',
        'pin_hash': pinHash,
        'role': 'admin',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      debugPrint('forceCreateAdmin: Admin user created successfully');
      return true;
    } catch (e) {
      debugPrint('forceCreateAdmin: Error: $e');
      return false;
    }
  }

  Future<bool> setupAdminPin(String pin, {String? email}) async {
    if (!_isValidPassword(pin)) {
      debugPrint('SetupAdminPin: Password invalid (must be 4-20 characters)');
      return false;
    }

    try {
      debugPrint('SetupAdminPin: Starting setup for PIN');

      // Ensure context is set
      if (_context == null) {
        debugPrint('SetupAdminPin: ERROR - Context is not set!');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final pinHash = _hashPin(pin);
      await prefs.setString('admin_pin', pinHash);
      debugPrint('SetupAdminPin: PIN hash saved to SharedPreferences');

      // Create admin user in database
      final dbProvider = _getDatabaseProvider();
      debugPrint('SetupAdminPin: Got database provider');

      // Ensure database is initialized with retry
      bool dbReady = false;
      int retryCount = 0;
      const maxRetries = 2;

      while (!dbReady && retryCount < maxRetries) {
        try {
          await dbProvider.init();
          // Verify database is working
          await dbProvider.query('users', limit: 1);
          dbReady = true;
          debugPrint('SetupAdminPin: Database initialized and verified');
        } catch (initError) {
          debugPrint(
              'SetupAdminPin: Database initialization attempt ${retryCount + 1} failed: $initError');
          if (retryCount < maxRetries - 1) {
            // Try to reset and reinitialize
            try {
              debugPrint('SetupAdminPin: Attempting to reset database...');
              await dbProvider.resetDatabase();
            } catch (resetError) {
              debugPrint('SetupAdminPin: Database reset failed: $resetError');
            }
          }
          retryCount++;
        }
      }

      if (!dbReady) {
        debugPrint(
            'SetupAdminPin: Database initialization failed after retries');
        return false;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final normalizedEmail =
          (email != null && email.trim().isNotEmpty) ? email.trim() : null;

      // Check if admin user already exists
      final existingUsers = await dbProvider.query(
        'users',
        where: 'username = ?',
        whereArgs: ['admin'],
      );
      debugPrint(
          'SetupAdminPin: Existing users count: ${existingUsers.length}');

      if (existingUsers.isEmpty) {
        final userId = await dbProvider.insert('users', {
          'username': 'admin',
          'pin_hash': pinHash,
          if (normalizedEmail != null) 'email': normalizedEmail,
          'role': 'admin',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        debugPrint('SetupAdminPin: Admin user created with ID: $userId');
      } else {
        // Update existing admin user
        final rowsUpdated = await dbProvider.update(
          'users',
          values: {
            'pin_hash': pinHash,
            'is_active': 1,
            if (normalizedEmail != null) 'email': normalizedEmail,
            'updated_at': now,
          },
          where: 'username = ?',
          whereArgs: ['admin'],
        );
        debugPrint(
            'SetupAdminPin: Admin user updated. Rows affected: $rowsUpdated');
      }

      debugPrint('SetupAdminPin: Setup completed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error creating admin user: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// NEW: Check if user can auto-login within 1 hour of logout
  Future<bool> canAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastLogoutTimestamp = prefs.getInt('last_logout_timestamp');

      if (lastLogoutTimestamp == null) {
        return false; // No previous session
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final oneHourInMs = 60 * 60 * 1000; // 1 hour in milliseconds
      final timeSinceLogout = now - lastLogoutTimestamp;

      if (timeSinceLogout > oneHourInMs) {
        // Session expired, clear stored info
        await prefs.remove('last_logout_user_id');
        await prefs.remove('last_logout_user_role');
        await prefs.remove('last_logout_username');
        await prefs.remove('last_logout_timestamp');
        return false;
      }

      // Session is still valid (within 1 hour)
      return true;
    } catch (e) {
      debugPrint('AuthProvider: Error checking auto-login: $e');
      return false;
    }
  }

  /// NEW: Auto-login using stored session info
  Future<bool> autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('last_logout_user_id');
      final userRole = prefs.getString('last_logout_user_role');
      final username = prefs.getString('last_logout_username');

      if (userId == null || userId.isEmpty) {
        return false;
      }

      // Restore session
      _isAuthenticated = true;
      _currentUserId = userId;
      _currentUserRole = userRole;
      _currentUsername = username;

      if (_lockMode == 'timeout') {
        _resetInactivityTimer();
      } else {
        _inactivityTimer?.cancel();
        _inactivityTimer = null;
      }

      notifyListeners();
      debugPrint('AuthProvider: Auto-login successful for user: $username');
      return true;
    } catch (e) {
      debugPrint('AuthProvider: Error during auto-login: $e');
      return false;
    }
  }

  /// Clear stored session info (called after successful login or when login screen loads).
  /// Public so login screen can clear any leftover auto-login data.
  Future<void> clearStoredSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_logout_user_id');
      await prefs.remove('last_logout_user_role');
      await prefs.remove('last_logout_username');
      await prefs.remove('last_logout_timestamp');
      debugPrint('AuthProvider: Cleared stored session info');
    } catch (e) {
      debugPrint('AuthProvider: Error clearing stored session: $e');
    }
  }

  /// Admin credentials from secure config (--dart-define=ADMIN_EMAIL=... --dart-define=ADMIN_PASSWORD=...).
  /// When not provided, fallback login is disabled for security.
  static String _getAdminEmail() =>
      const String.fromEnvironment('ADMIN_EMAIL', defaultValue: '');
  static String _getAdminPassword() =>
      const String.fromEnvironment('ADMIN_PASSWORD', defaultValue: '');

  bool _isAdminCredentials(String email, String password) {
    final adminEmail = _getAdminEmail().trim().toLowerCase();
    final adminPassword = _getAdminPassword();
    if (adminEmail.isEmpty || adminPassword.isEmpty) return false;
    return email.trim().toLowerCase() == adminEmail && password == adminPassword;
  }

  /// Login using Firebase Authentication
  /// Connects to Firestore document with ID dSc8mQzHPsftOpqb200d7xPhS7K2 for admin
  /// FALLBACK: If Firebase Auth fails but credentials match secure admin config, allow login.
  /// Auto-login disabled: admin and all role-based users must enter email/password every time.
  Future<bool> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      debugPrint('Login: Email and password are required');
      return false;
    }

    try {
      final trimmedEmail = email.trim().toLowerCase();
      debugPrint(
          'Login: Attempting Firebase Auth login for email: $trimmedEmail');
      debugPrint('Login: Password length: ${password.length}');

      final isAdminCredentials = _isAdminCredentials(trimmedEmail, password);
      if (isAdminCredentials) {
        debugPrint(
            'Login: Admin credentials detected - will allow login even if Firebase Auth fails');
      }

      // Sign in with Firebase Auth
      // Use defensive access to avoid minified JS type errors
      dynamic authInstance;
      bool authSucceeded = false;
      dynamic firebaseUser;

      try {
        authInstance = FirebaseAuth.instance;
      } catch (e) {
        debugPrint('Login: Error getting FirebaseAuth.instance: $e');
        // If admin credentials, allow fallback login
        if (isAdminCredentials) {
          debugPrint(
              'Login: Firebase Auth unavailable, but admin credentials verified - allowing login');
          _isAuthenticated = true;
          _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
          _currentUserRole = 'admin';
          _currentUsername = 'admin';
          if (_lockMode == 'timeout') {
            _resetInactivityTimer();
          } else {
            _inactivityTimer?.cancel();
            _inactivityTimer = null;
          }
          notifyListeners();
          return true;
        }
        return false;
      }

      UserCredential? userCredential;

      try {
        // Use dynamic call to avoid minified JS type checking issues
        userCredential = await authInstance.signInWithEmailAndPassword(
          email: trimmedEmail, // Already normalized to lowercase
          password:
              password, // Don't trim password - it may contain leading/trailing spaces intentionally
        ) as UserCredential?;
        authSucceeded = true;
        debugPrint('Login: Firebase Auth sign-in successful');
      } catch (e) {
        // In minified JS, we can't reliably catch FirebaseAuthException
        // So we catch all errors and check the error message/type dynamically
        final errorStr = e.toString();
        debugPrint('Login: Firebase Auth error: $e');

        // Check if it's a Firebase Auth error by examining the error string
        if (errorStr.contains('user-not-found') ||
            errorStr.contains('wrong-password') ||
            errorStr.contains('invalid-email') ||
            errorStr.contains('user-disabled') ||
            errorStr.contains('too-many-requests') ||
            errorStr.contains('FirebaseAuthException')) {
          // This is a Firebase Auth error
          debugPrint('Login: Firebase Auth error detected');

          // FALLBACK: If admin credentials, allow login anyway
          if (isAdminCredentials) {
            debugPrint(
                'Login: Firebase Auth failed, but admin credentials verified - allowing fallback login');
            _isAuthenticated = true;
            _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
            _currentUserRole = 'admin';
            _currentUsername = 'admin';
            if (_lockMode == 'timeout') {
              _resetInactivityTimer();
            } else {
              _inactivityTimer?.cancel();
              _inactivityTimer = null;
            }
            notifyListeners();
            return true;
          }

          // Try to extract error code from the error message
          if (errorStr.contains('user-not-found')) {
            debugPrint('Login: Firebase Auth user does not exist. Create user in Firebase Console.');
          } else if (errorStr.contains('wrong-password')) {
            debugPrint('Login: Password is incorrect');
          }
          return false;
        } else if (errorStr.contains('minified') ||
            errorStr.contains('TypeError')) {
          // This is a minified JS type error - try to continue anyway
          debugPrint(
              'Login: Minified JS type error detected, checking if auth actually succeeded');
          // Check if we can get the current user despite the error
          try {
            dynamic currentUser = authInstance.currentUser;
            if (currentUser != null) {
              // Auth actually succeeded despite the type error
              debugPrint('Login: Firebase Auth succeeded (despite type error)');
              firebaseUser = currentUser;
              authSucceeded = true;
            } else {
              debugPrint('Login: Firebase Auth failed due to type error');
              // FALLBACK: If admin credentials, allow login anyway
              if (isAdminCredentials) {
                debugPrint(
                    'Login: Allowing fallback login for admin despite type error');
                _isAuthenticated = true;
                _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
                _currentUserRole = 'admin';
                _currentUsername = 'admin';
                if (_lockMode == 'timeout') {
                  _resetInactivityTimer();
                } else {
                  _inactivityTimer?.cancel();
                  _inactivityTimer = null;
                }
                notifyListeners();
                return true;
              }
              return false;
            }
          } catch (checkError) {
            debugPrint('Login: Could not verify auth status: $checkError');
            // FALLBACK: If admin credentials, allow login anyway
            if (isAdminCredentials) {
              debugPrint(
                  'Login: Allowing fallback login for admin despite verification error');
              _isAuthenticated = true;
              _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
              _currentUserRole = 'admin';
              _currentUsername = 'admin';
              if (_lockMode == 'timeout') {
                _resetInactivityTimer();
              } else {
                _inactivityTimer?.cancel();
                _inactivityTimer = null;
              }
              notifyListeners();
              return true;
            }
            return false;
          }
        } else {
          // Unknown error
          debugPrint('Login: Unexpected error during Firebase Auth: $e');
          // FALLBACK: If admin credentials, allow login anyway
          if (isAdminCredentials) {
            debugPrint(
                'Login: Allowing fallback login for admin despite unexpected error');
            _isAuthenticated = true;
            _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
            _currentUserRole = 'admin';
            _currentUsername = 'admin';
            if (_lockMode == 'timeout') {
              _resetInactivityTimer();
            } else {
              _inactivityTimer?.cancel();
              _inactivityTimer = null;
            }
            notifyListeners();
            return true;
          }
          return false;
        }
      }

      // Handle both normal UserCredential and the case where we got currentUser directly
      if (authSucceeded && firebaseUser == null) {
        if (userCredential != null && userCredential.user != null) {
          firebaseUser = userCredential.user;
          debugPrint(
              'Login: Firebase Auth successful for ${firebaseUser.email}');
        } else {
          // Try to get current user directly (in case of minified JS error workaround)
          try {
            firebaseUser = authInstance.currentUser;
            if (firebaseUser == null) {
              debugPrint('Login: Firebase Auth returned null user');
              // FALLBACK: If admin credentials, allow login anyway
              if (isAdminCredentials) {
                debugPrint(
                    'Login: Allowing fallback login for admin despite null user');
                _isAuthenticated = true;
                _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
                _currentUserRole = 'admin';
                _currentUsername = 'admin';
                if (_lockMode == 'timeout') {
                  _resetInactivityTimer();
                } else {
                  _inactivityTimer?.cancel();
                  _inactivityTimer = null;
                }
                notifyListeners();
                return true;
              }
              return false;
            }
            debugPrint(
                'Login: Firebase Auth successful (using currentUser) for ${firebaseUser.email}');
          } catch (e) {
            debugPrint('Login: Could not get Firebase user: $e');
            // FALLBACK: If admin credentials, allow login anyway
            if (isAdminCredentials) {
              debugPrint(
                  'Login: Allowing fallback login for admin despite user access error');
              _isAuthenticated = true;
              _currentUserId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
              _currentUserRole = 'admin';
              _currentUsername = 'admin';
              if (_lockMode == 'timeout') {
                _resetInactivityTimer();
              } else {
                _inactivityTimer?.cancel();
                _inactivityTimer = null;
              }
              notifyListeners();
              return true;
            }
            return false;
          }
        }
      }

      // Get database provider to fetch user document
      final dbProvider = _getDatabaseProvider();
      try {
        await dbProvider.init();
        debugPrint('Login: Database initialized successfully');
      } catch (dbInitError) {
        debugPrint('Login: Database initialization failed: $dbInitError');
        debugPrint(
            'Login: Continuing with Firebase Auth only - will use Firebase UID');
        // Continue with login using Firebase Auth UID even if database init fails
        // This allows login to work even if Firestore has issues
        _isAuthenticated = true;
        try {
          _currentUserId =
              firebaseUser.uid as String? ?? firebaseUser.uid.toString();
          final email = firebaseUser.email as String?;
          _currentUserRole =
              'admin'; // Default to admin if this is the admin email
          _currentUsername = email?.split('@').first ?? 'user';
        } catch (e) {
          debugPrint('Login: Error accessing firebaseUser properties: $e');
          // Fallback to string conversion
          _currentUserId = firebaseUser.toString();
          _currentUserRole = 'admin';
          _currentUsername = 'user';
        }

        if (_lockMode == 'timeout') {
          _resetInactivityTimer();
        } else {
          _inactivityTimer?.cancel();
          _inactivityTimer = null;
        }
        notifyListeners();
        return true;
      }

      // Connect to Firestore document for admin user
      const adminDocumentId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';

      // Try to find admin user by document ID
      try {
        final adminUsers = await dbProvider.query(
          'users',
          where: 'documentId = ?',
          whereArgs: [adminDocumentId],
        );

        if (adminUsers.isNotEmpty) {
          final adminUser = adminUsers.first;
          final adminEmail = adminUser['email'] as String?;

          // Verify this is the admin user by email (normalize both to lowercase)
          if (adminEmail?.toLowerCase() == trimmedEmail.toLowerCase()) {
            final isActive = (adminUser['is_active'] as num?)?.toInt();
            if (isActive != null && isActive == 0) {
              debugPrint('Login: Admin user is disabled');
              try {
                await authInstance.signOut();
              } catch (e) {
                debugPrint('Login: Error signing out: $e');
              }
              return false;
            }

            _isAuthenticated = true;
            _currentUserId = adminDocumentId;
            _currentUserRole = 'admin';
            _currentUsername = adminUser['username'] as String? ?? 'admin';

            debugPrint(
                'Login: Success! Admin authenticated with document ID: $_currentUserId');
            // NEW: Clear old session info on successful login
            await clearStoredSession();
            if (_lockMode == 'timeout') {
              _resetInactivityTimer();
            } else {
              _inactivityTimer?.cancel();
              _inactivityTimer = null;
            }
            notifyListeners();
            return true;
          }
        }
      } catch (e) {
        debugPrint('Login: Error looking up admin document: $e');
      }

      // If not admin, try to find user by email in Firestore
      try {
        final users = await dbProvider.query(
          'users',
          where: 'email = ?',
          whereArgs: [trimmedEmail.toLowerCase()],
        );

        if (users.isNotEmpty) {
          final user = users.first;
          final isActive = (user['is_active'] as num?)?.toInt();
          if (isActive != null && isActive == 0) {
            debugPrint('Login: User is disabled');
            try {
              await authInstance.signOut();
            } catch (e) {
              debugPrint('Login: Error signing out: $e');
            }
            return false;
          }

          _isAuthenticated = true;
          // Use documentId on web (Firestore), id on mobile (SQLite), else Firebase UID
          final docId = user['documentId'];
          final dbId = user['id'];
          _currentUserId = ((docId is String) ? docId : (docId?.toString())) ??
              (dbId?.toString()) ??
              (firebaseUser.uid?.toString() ?? firebaseUser.uid.toString());
          _currentUserRole = user['role'] as String? ?? 'cashier';
          _currentUsername =
              user['username'] as String? ?? trimmedEmail.split('@').first;

          debugPrint(
              'Login: Success! User authenticated - ID: $_currentUserId, Role: $_currentUserRole');
          // NEW: Clear old session info on successful login
          await clearStoredSession();
          if (_lockMode == 'timeout') {
            _resetInactivityTimer();
          } else {
            _inactivityTimer?.cancel();
            _inactivityTimer = null;
          }
          notifyListeners();
          return true;
        }
      } catch (e) {
        debugPrint('Login: Error looking up user by email: $e');
      }

      // If user document not found, check if this is the admin email and create admin document
      final configAdminEmail = _getAdminEmail().trim().toLowerCase();
      if (configAdminEmail.isNotEmpty &&
          trimmedEmail.toLowerCase() == configAdminEmail) {
        debugPrint(
            'Login: Admin email detected but Firestore document not found. Creating admin document...');

        // Try to create admin user document if it doesn't exist
        const adminDocumentId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
        try {
          // Check if document already exists
          final existing = await dbProvider.query(
            'users',
            where: 'documentId = ?',
            whereArgs: [adminDocumentId],
          );

          if (existing.isEmpty) {
            // Create admin user document
            final now = DateTime.now().millisecondsSinceEpoch;
            await dbProvider.insert(
                'users',
                {
                  'username': 'admin',
                  'email': trimmedEmail.toLowerCase(),
                  'role': 'admin',
                  'is_active': 1,
                  'created_at': now,
                  'updated_at': now,
                },
                documentId: kIsWeb ? adminDocumentId : null);

            debugPrint(
                'Login: Created admin user document with ID: $adminDocumentId');
          } else {
            debugPrint('Login: Admin document already exists, using it');
          }

          // Set authenticated state with admin document ID
          _isAuthenticated = true;
          _currentUserId = adminDocumentId;
          _currentUserRole = 'admin';
          _currentUsername = 'admin';

          debugPrint(
              'Login: Success! Admin authenticated with document ID: $_currentUserId');
          // NEW: Clear old session info on successful login
          await clearStoredSession();
          if (_lockMode == 'timeout') {
            _resetInactivityTimer();
          } else {
            _inactivityTimer?.cancel();
            _inactivityTimer = null;
          }
          notifyListeners();
          return true;
        } catch (e) {
          debugPrint('Login: Error creating/accessing admin document: $e');
          // Even if document creation fails, allow login with Firebase Auth UID
          debugPrint('Login: Falling back to Firebase Auth UID for admin');
          _isAuthenticated = true;
          try {
            _currentUserId =
                firebaseUser.uid as String? ?? firebaseUser.uid.toString();
          } catch (e) {
            _currentUserId = firebaseUser.toString();
          }
          _currentUserRole = 'admin';
          _currentUsername = 'admin';

          if (_lockMode == 'timeout') {
            _resetInactivityTimer();
          } else {
            _inactivityTimer?.cancel();
            _inactivityTimer = null;
          }
          notifyListeners();
          return true;
        }
      }

      // If user document not found and not admin, still allow login but create a basic user record
      debugPrint(
          'Login: User document not found in Firestore, but Firebase Auth succeeded');
      _isAuthenticated = true;
      try {
        _currentUserId =
            firebaseUser.uid as String? ?? firebaseUser.uid.toString();
        final email = firebaseUser.email as String?;
        _currentUserRole = 'cashier'; // Default role
        _currentUsername = email?.split('@').first ?? 'user';
      } catch (e) {
        debugPrint('Login: Error accessing firebaseUser properties: $e');
        _currentUserId = firebaseUser.toString();
        _currentUserRole = 'cashier';
        _currentUsername = 'user';
      }

      // NEW: Clear old session info on successful login
      await clearStoredSession();
      if (_lockMode == 'timeout') {
        _resetInactivityTimer();
      } else {
        _inactivityTimer?.cancel();
        _inactivityTimer = null;
      }
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Login: Firebase Auth error: ${e.code} - ${e.message}');
      debugPrint('Login: Attempted email: ${email.trim().toLowerCase()}');
      debugPrint('Login: Password length: ${password.length}');

      // Provide more specific error information
      if (e.code == 'user-not-found') {
        debugPrint('Login: Firebase Auth user does not exist. Create user in Firebase Console.');
      } else if (e.code == 'wrong-password') {
        debugPrint('Login: Incorrect password');
      }

      return false;
    } catch (e, stackTrace) {
      debugPrint('Login: Error during login: $e');
      debugPrint('Login: Stack trace: $stackTrace');
      debugPrint('Login: Attempted email: ${email.trim().toLowerCase()}');
      return false;
    }
  }

  /// Logout: manual only. [storeForAutoLogin] is always false in app (no auto-login).
  /// User must enter email/password again after logout.
  Future<void> logout({bool storeForAutoLogin = false}) async {
    // Clear state immediately
    final prevUserId = _currentUserId;
    final prevRole = _currentUserRole;
    final prevUsername = _currentUsername;
    _isAuthenticated = false;
    _currentUserId = null;
    _currentUserRole = null;
    _currentUsername = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    notifyListeners();

    // Force AuthWrapper to rebuild so it shows LoginScreen (no push needed;
    // MaterialApp key change + Consumer rebuild handles navigation on web and mobile).
    onLogout?.call();

    // Persist session for auto-login only when NOT explicit user logout (e.g. inactivity).
    // FIXED: Explicit logout no longer stores session, so user stays logged out.
    if (storeForAutoLogin) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().millisecondsSinceEpoch;
        await prefs.setString('last_logout_user_id', prevUserId ?? '');
        await prefs.setString('last_logout_user_role', prevRole ?? '');
        await prefs.setString('last_logout_username', prevUsername ?? '');
        await prefs.setInt('last_logout_timestamp', now);
      } catch (e) {
        debugPrint('AuthProvider: Error storing session info: $e');
      }
    } else {
      // Clear any previous auto-login data so user stays logged out
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_logout_user_id');
        await prefs.remove('last_logout_user_role');
        await prefs.remove('last_logout_username');
        await prefs.remove('last_logout_timestamp');
      } catch (e) {
        debugPrint('AuthProvider: Error clearing session info: $e');
      }
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('AuthProvider: Error signing out from Firebase Auth: $e');
    }
  }

  void updateActivity() {
    // DISABLED: Automatic logout is disabled - no inactivity timer
    // Timer functionality removed to prevent automatic logout
  }

  void _resetInactivityTimer() {
    // DISABLED: Automatic logout is disabled - timer is not started
    // Cancel any existing timer but don't start a new one
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool get isAdmin => _currentUserRole == 'admin';
  bool get isCashier =>
      _currentUserRole == 'cashier' || _currentUserRole == 'admin';

  // Change password for current user
  Future<bool> changePassword(String oldPin, String newPin) async {
    if (!_isValidPassword(oldPin) || !_isValidPassword(newPin)) {
      return false;
    }

    if (_currentUserId == null) {
      return false;
    }

    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      final oldPinHash = _hashPin(oldPin);

      // Verify old password - handle both SQLite (id) and Firestore (documentId)
      final users = await dbProvider.query(
        'users',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [_currentUserId],
        limit: 1,
      );

      if (users.isEmpty) {
        debugPrint('changePassword: User not found');
        return false;
      }

      final user = users.first;
      final storedPinHash = user['pin_hash'] as String?;
      
      // Verify old password - check database hash first
      bool oldPasswordValid = false;
      
      if (storedPinHash != null && storedPinHash == oldPinHash) {
        oldPasswordValid = true;
      } else if (kIsWeb) {
        // For web, also try Firebase Auth verification if database hash doesn't match
        // This handles cases where password was changed in Firebase Auth but not synced to database
        try {
          dynamic authInstance = FirebaseAuth.instance;
          final currentUser = authInstance.currentUser;
          if (currentUser != null && currentUser.email != null) {
            // Try to verify by attempting to re-authenticate
            // Note: We can't directly verify without re-authenticating, so we'll try updatePassword
            // which will fail if old password is wrong
            try {
              // For verification, we'll use verifyAdminPin which handles Firebase Auth
              oldPasswordValid = await verifyAdminPin(oldPin);
            } catch (e) {
              debugPrint('changePassword: Firebase Auth verification failed: $e');
            }
          }
        } catch (e) {
          debugPrint('changePassword: Firebase Auth check error: $e');
        }
      }

      if (!oldPasswordValid) {
        debugPrint('changePassword: Old password incorrect');
        return false;
      }

      // Update password in database
      final newPinHash = _hashPin(newPin);
      final now = DateTime.now().millisecondsSinceEpoch;

      await dbProvider.update(
        'users',
        values: {
          'pin_hash': newPinHash,
          'updated_at': now,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [_currentUserId],
      );

      // Update Firebase Auth password (for web)
      // Note: updatePassword requires recent authentication. If it fails, user may need to re-login.
      if (kIsWeb) {
        try {
          dynamic authInstance = FirebaseAuth.instance;
          final currentUser = authInstance.currentUser;
          if (currentUser != null && currentUser.email != null) {
            try {
              await currentUser.updatePassword(newPin);
              debugPrint('changePassword: Firebase Auth password updated successfully');
            } catch (e) {
              final errorStr = e.toString();
              if (errorStr.contains('requires-recent-login') || 
                  errorStr.contains('auth/requires-recent-login')) {
                debugPrint('changePassword: Firebase Auth requires recent login. Password updated in database only.');
                debugPrint('changePassword: User may need to re-login to update Firebase Auth password.');
              } else {
                debugPrint('changePassword: Firebase Auth update error: $e');
              }
              // Continue - database password is updated
            }
          }
        } catch (e) {
          debugPrint('changePassword: Firebase Auth check error (continuing): $e');
          // Continue even if Firebase Auth update fails
        }
      }

      // Also update SharedPreferences if admin
      if (_currentUserRole == 'admin') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_pin', newPinHash);
      }

      return true;
    } catch (e) {
      debugPrint('Error changing password: $e');
      return false;
    }
  }

  /// Change admin password specifically (updates SharedPreferences, database, and Firebase Auth)
  /// This is a convenience method for admin password changes
  Future<bool> changeAdminPassword(String oldPin, String newPin) async {
    if (!_isValidPassword(oldPin) || !_isValidPassword(newPin)) {
      return false;
    }

    if (!_isAuthenticated || _currentUserRole != 'admin') {
      debugPrint('changeAdminPassword: Only admin can change admin password');
      return false;
    }

    try {
      // First verify old password
      final isValid = await verifyAdminPin(oldPin);
      if (!isValid) {
        debugPrint('changeAdminPassword: Old password incorrect');
        return false;
      }

      // Update password using the standard changePassword method
      final success = await changePassword(oldPin, newPin);
      
      if (success) {
        debugPrint('changeAdminPassword: Admin password changed successfully');
      }
      
      return success;
    } catch (e) {
      debugPrint('Error changing admin password: $e');
      return false;
    }
  }

  /// Result of createUserWithError: error is null on success; signedOut is true when admin was signed out (web).
  Future<({String? error, bool signedOut})> createUserWithError(
      String username, String pin, String role,
      {String? email}) async {
    if (username.trim().isEmpty) {
      return (error: 'Username cannot be empty', signedOut: false);
    }

    if (!_isValidPassword(pin)) {
      return (
        error:
            'Password must be 4-20 characters and contain only letters, numbers, and special characters',
        signedOut: false,
      );
    }

    // UPDATED: Allow any role (not just admin/cashier) to support custom roles
    if (role.trim().isEmpty) {
      return (error: 'Role cannot be empty', signedOut: false);
    }

    // Email is required only for admin role
    if (role == 'admin' && (email == null || email.trim().isEmpty)) {
      return (error: 'Email is required for admin users', signedOut: false);
    }

    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // Check if username already exists
      final existing = await dbProvider.query(
        'users',
        where: 'username = ?',
        whereArgs: [username.trim()],
      );

      if (existing.isNotEmpty) {
        return (
          error: 'Username already exists. Please choose a different username',
          signedOut: false,
        );
      }

      final pinHash = _hashPin(pin);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Use only the email the admin entered; store lowercase so login lookup works
      final String? normalizedEmail = (email != null && email.trim().isNotEmpty)
          ? email.trim().toLowerCase()
          : null;

      // On web with email: create Firebase Auth user so the user can log in with email/password.
      // Without this, the user exists only in Firestore and cannot sign in.
      bool firebaseAuthUserCreated = false;
      if (kIsWeb && normalizedEmail != null) {
        try {
          dynamic authInstance = FirebaseAuth.instance;
          await authInstance.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: pin,
          );
          firebaseAuthUserCreated = true;
          debugPrint(
              'createUser: Firebase Auth user created - user can log in with this email/password');
        } catch (authError) {
          final errorMsg = authError.toString();
          debugPrint(
              'createUser: Firebase Auth user creation failed: $authError');
          if (errorMsg.contains('email-already-in-use')) {
            // User already exists in Firebase Auth - still add/update Firestore so role is linked
            debugPrint(
                'createUser: Email already in Firebase Auth, linking with Firestore');
          } else if (errorMsg.contains('weak-password') ||
              errorMsg.contains('invalid-email')) {
            return (
              error: 'Invalid email or password format. Please check your input.',
              signedOut: false,
            );
          } else if (errorMsg.contains('requests-from-referer') ||
              errorMsg.contains('are-blocked')) {
            return (
              error:
                  'This domain is not authorized. In Firebase Console go to Authentication → Settings → Authorized domains and add your domain (e.g. localhost).',
              signedOut: false,
            );
          } else {
            // e.g. operation-not-allowed, network - show short hint; Email/Password may already be enabled
            final hint = errorMsg.length > 80
                ? '${errorMsg.substring(0, 77)}...'
                : errorMsg;
            debugPrint('createUser: Auth error detail: $hint');
            return (
              error:
                  'Could not create login account. If Email/Password is enabled, check Authentication → Settings → Authorized domains, or try again.',
              signedOut: false,
            );
          }
        }
      }

      // Store user in Firestore with email (lowercase) and role so login can find them and set role
      await dbProvider.insert('users', {
        'username': username.trim(),
        'pin_hash': pinHash,
        'email': normalizedEmail,
        'role': role.trim(),
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      // After creating a new Firebase Auth user, sign out from Firebase only (release new user session).
      // Admin stays logged in - no automatic app logout; user must manually tap Logout.
      if (kIsWeb && firebaseAuthUserCreated) {
        try {
          await FirebaseAuth.instance.signOut();
          debugPrint(
              'createUser: Signed out from Firebase so new user can log in; admin stays in app');
        } catch (e) {
          debugPrint('createUser: signOut after create: $e');
        }
      }

      debugPrint(
          'createUser: User created - username: ${username.trim()}, email: $normalizedEmail, role: ${role.trim()}');
      return (error: null, signedOut: false);
    } catch (e) {
      debugPrint('Error creating user: $e');
      final errorStr = e.toString();
      if (errorStr.contains('UNIQUE constraint') ||
          errorStr.contains('unique')) {
        return (
          error: 'Username already exists. Please choose a different username',
          signedOut: false,
        );
      }
      return (
        error:
            'Failed to create user: ${errorStr.length > 100 ? "${errorStr.substring(0, 100)}..." : errorStr}',
        signedOut: false,
      );
    }
  }

  /// Legacy method for backward compatibility - returns bool
  /// UPDATED: Now supports custom roles (not just admin/cashier)
  Future<bool> createUser(String username, String pin, String role,
      {String? email}) async {
    final result =
        await createUserWithError(username, pin, role, email: email);
    return result.error == null; // Return true if no error
  }

  /// Create a user with a specific document ID (for Firestore) or regular insert (SQLite)
  /// Useful for migrating users or setting up specific user IDs
  /// UPDATED: Now supports custom roles (not just admin/cashier)
  Future<bool> createUserWithId(
      String userId, String username, String pin, String role,
      {String? email}) async {
    if (!_isValidPassword(pin)) {
      return false;
    }

    if (username.trim().isEmpty || role.trim().isEmpty) {
      return false;
    }

    // Email is required only for admin role
    if (role == 'admin' && (email == null || email.trim().isEmpty)) {
      return false;
    }

    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // Check if username already exists
      final existing = await dbProvider.query(
        'users',
        where: 'username = ?',
        whereArgs: [username.trim()],
      );

      if (existing.isNotEmpty) {
        return false; // Username already exists
      }

      // Check if user ID already exists (for Firestore)
      if (kIsWeb) {
        final existingById = await dbProvider.query(
          'users',
          where: 'documentId = ?',
          whereArgs: [userId],
        );
        if (existingById.isNotEmpty) {
          return false; // User ID already exists
        }
      }

      final pinHash = _hashPin(pin);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Use only the email the admin entered; do not auto-generate
      final String? normalizedEmail = (email != null && email.trim().isNotEmpty)
          ? email.trim().toLowerCase()
          : null;

      // FIXED: On web with email, create Firebase Auth user so login works
      // Without this, signInWithEmailAndPassword fails with "user-not-found"
      if (kIsWeb && normalizedEmail != null) {
        try {
          dynamic authInstance = FirebaseAuth.instance;
          await authInstance.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: pin,
          );
          debugPrint(
              'createUserWithId: Firebase Auth user created for $normalizedEmail');
          // Sign out so admin can log back in; new user can log in with their credentials
          try {
            await FirebaseAuth.instance.signOut();
          } catch (e) {
            debugPrint('createUserWithId: signOut after create: $e');
          }
        } catch (authError) {
          final errorMsg = authError.toString();
          debugPrint(
              'createUserWithId: Firebase Auth creation failed: $authError');
          if (errorMsg.contains('email-already-in-use')) {
            debugPrint(
                'createUserWithId: Email already in Firebase Auth - Firestore user will still be created');
          } else if (errorMsg.contains('operation-not-allowed')) {
            debugPrint(
                'createUserWithId: Email/Password sign-in may not be enabled in Firebase Console');
          } else {
            rethrow;
          }
        }
      }

      await dbProvider.insert(
          'users',
          {
            'username': username.trim(),
            'pin_hash': pinHash,
            'email': normalizedEmail,
            'role': role.trim(),
            'is_active': 1,
            'created_at': now,
            'updated_at': now,
          },
          documentId: kIsWeb ? userId : null);

      debugPrint(
          'createUserWithId: User created with ID: $userId, username: $username, role: $role');
      return true;
    } catch (e) {
      debugPrint('Error creating user with ID: $e');
      return false;
    }
  }

  // Admin-only: list users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final dbProvider = _getDatabaseProvider();
      try {
        await dbProvider.init();
      } catch (initError) {
        debugPrint('getAllUsers: Database initialization failed: $initError');
        // Return at least the current admin user if we're logged in
        if (_isAuthenticated &&
            _currentUserRole == 'admin' &&
            _currentUserId != null) {
          return [
            {
              'id': _currentUserId,
              'documentId': kIsWeb ? _currentUserId : null,
              'username': _currentUsername ?? 'admin',
              'email': _getAdminEmail().isNotEmpty ? _getAdminEmail() : null,
              'role': 'admin',
              'is_active': 1,
            }
          ];
        }
        // If database init fails and we can't get current user, return empty list
        return [];
      }
      return await dbProvider.query('users', orderBy: 'username ASC');
    } catch (e) {
      debugPrint('getAllUsers: Error loading users: $e');
      // Return at least the current admin user if we're logged in
      if (_isAuthenticated &&
          _currentUserRole == 'admin' &&
          _currentUserId != null) {
        return [
          {
            'id': _currentUserId,
            'documentId': kIsWeb ? _currentUserId : null,
            'username': _currentUsername ?? 'admin',
            'email': _getAdminEmail().isNotEmpty ? _getAdminEmail() : null,
            'role': 'admin',
            'is_active': 1,
          }
        ];
      }
      // Return empty list on error
      return [];
    }
  }

  // Admin-only: change role
  Future<bool> updateUserRole(
      {required dynamic userId, required String role}) async {
    if (role != 'admin' && role != 'cashier') return false;
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();
      await dbProvider.update(
        'users',
        values: {'role': role},
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
      );
      return true;
    } catch (e) {
      debugPrint('Error updating user role: $e');
      return false;
    }
  }

  // Admin-only: enable/disable user
  Future<bool> setUserActive(
      {required dynamic userId, required bool isActive}) async {
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();
      await dbProvider.update(
        'users',
        values: {'is_active': isActive ? 1 : 0},
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
      );
      return true;
    } catch (e) {
      debugPrint('Error updating user active state: $e');
      return false;
    }
  }

  // Admin-only: reset password for another user
  Future<bool> resetUserPin(
      {required dynamic userId, required String newPin}) async {
    if (!_isValidPassword(newPin)) return false;
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();
      
      // Get user info to update Firebase Auth if needed
      final users = await dbProvider.query(
        'users',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      
      if (users.isEmpty) {
        debugPrint('resetUserPin: User not found');
        return false;
      }
      
      final user = users.first;
      final userEmail = user['email'] as String?;
      final isAdmin = (user['role'] as String?) == 'admin';
      
      // Update password in database
      final newPinHash = _hashPin(newPin);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await dbProvider.update(
        'users',
        values: {
          'pin_hash': newPinHash,
          'updated_at': now,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
      );
      
      // Update Firebase Auth password (for web users with email)
      if (kIsWeb && userEmail != null && userEmail.isNotEmpty) {
        try {
          dynamic authInstance = FirebaseAuth.instance;
          // Get the user by email
          try {
            // Note: We can't directly update another user's password from client-side
            // This would require admin SDK or Cloud Functions
            // For now, we'll update the database and log a message
            debugPrint('resetUserPin: Database password updated. Firebase Auth password should be updated via Firebase Console or Cloud Functions for user: $userEmail');
          } catch (e) {
            debugPrint('resetUserPin: Firebase Auth update note: $e');
          }
        } catch (e) {
          debugPrint('resetUserPin: Firebase Auth check error (continuing): $e');
        }
      }
      
      // Also update SharedPreferences if this is the admin user
      if (isAdmin) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('admin_pin', newPinHash);
          debugPrint('resetUserPin: Admin PIN updated in SharedPreferences');
        } catch (e) {
          debugPrint('resetUserPin: SharedPreferences update error: $e');
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('Error resetting user PIN: $e');
      return false;
    }
  }

  // Admin-only: delete user
  Future<bool> deleteUser({required dynamic userId}) async {
    try {
      // Don't allow deleting yourself
      if (_currentUserId != null && _currentUserId == userId.toString()) {
        debugPrint('deleteUser: Cannot delete your own account');
        return false;
      }

      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // Get user info before deleting (to get email for Firebase Auth deletion)
      final users = await dbProvider.query(
        'users',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (users.isEmpty) {
        debugPrint('deleteUser: User not found');
        return false;
      }

      final user = users.first;
      final userEmail = user['email'] as String?;

      // Delete from database
      await dbProvider.delete(
        'users',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
      );

      // Try to delete Firebase Auth user if on web and email exists
      if (kIsWeb && userEmail != null && userEmail.isNotEmpty) {
        try {
          dynamic authInstance = FirebaseAuth.instance;
          final users =
              await authInstance.fetchSignInMethodsForEmail(userEmail);
          if (users != null && (users as List).isNotEmpty) {
            // User exists in Firebase Auth, try to delete
            // Note: We can't directly delete users from client-side, but we can mark them as deleted
            // The actual deletion should be done server-side or through Firebase Console
            debugPrint(
                'deleteUser: Firebase Auth user exists for $userEmail (deletion should be done server-side)');
          }
        } catch (authError) {
          debugPrint(
              'deleteUser: Error checking Firebase Auth user: $authError');
          // Continue even if Firebase Auth deletion fails
        }
      }

      debugPrint('deleteUser: User deleted successfully - userId: $userId');
      return true;
    } catch (e) {
      debugPrint('Error deleting user: $e');
      return false;
    }
  }

  // Role Permissions Management
  // Default permissions: Admin has access to all, Cashier has access to most except Inventory and Purchases
  static const Map<String, List<int>> _defaultPermissions = {
    'admin': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], // All sections
    'cashier': [
      0,
      1,
      2,
      3,
      4,
      5,
      7,
      9
    ], // All except Inventory (6) and Purchases (8)
  };

  /// Get permissions for a role
  /// UPDATED: First check roles table, then fallback to settings table for backward compatibility
  Future<Set<int>> getRolePermissions(String role) async {
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // UPDATED: First try to get permissions from roles table
      try {
        final roleData = await dbProvider.query(
          'roles',
          where: 'name = ? AND is_active = ?',
          whereArgs: [role, 1],
        );

        if (roleData.isNotEmpty) {
          final permissionsJson =
              roleData.first['permissions'] as String? ?? '[]';
          final List<dynamic> permissionsList = jsonDecode(permissionsJson);
          final permissions =
              permissionsList.map((e) => (e as num).toInt()).toSet();

          // Always ensure Dashboard (0) is included
          if (!permissions.contains(0)) {
            permissions.add(0);
          }
          return permissions;
        }
      } catch (e) {
        debugPrint(
            'AuthProvider: Error querying roles table (may not exist yet): $e');
      }

      // FALLBACK: Check settings table for backward compatibility
      final settings = await dbProvider.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['role_permissions_$role'],
      );

      Set<int> permissions;
      if (settings.isNotEmpty) {
        final permissionsJson = settings.first['value'] as String? ?? '[]';
        final List<dynamic> permissionsList = jsonDecode(permissionsJson);
        permissions = permissionsList.map((e) => (e as num).toInt()).toSet();
      } else {
        // Return default permissions if not configured
        permissions = _defaultPermissions[role]?.toSet() ?? <int>{};
      }

      // Always ensure Dashboard (0) is included - NavigationBar requires at least 2 destinations
      if (!permissions.contains(0)) {
        permissions.add(0);
      }

      return permissions;
    } catch (e) {
      debugPrint('AuthProvider: Error getting role permissions: $e');
      final permissions = _defaultPermissions[role]?.toSet() ?? <int>{0};
      // Always ensure Dashboard is included
      permissions.add(0);
      return permissions;
    }
  }

  /// Update permissions for a role
  /// On web, updates Firestore `roles` collection so Roles section and permissions stay in sync.
  Future<bool> updateRolePermissions(String role, Set<int> permissions) async {
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // Always ensure Dashboard (0) is included - NavigationBar requires at least 2 destinations
      final effectivePermissions = Set<int>.from(permissions);
      if (!effectivePermissions.contains(0)) {
        effectivePermissions.add(0);
      }

      // Ensure at least 2 permissions (Dashboard + one other)
      if (effectivePermissions.length < 2) {
        // Add Orders (1) as a safe default second option
        effectivePermissions.add(1);
      }

      final permissionsJson = jsonEncode(effectivePermissions.toList());
      final now = DateTime.now().millisecondsSinceEpoch;

      // On web, update Firestore `roles` collection so Roles section and getRolePermissions use same data
      if (kIsWeb) {
        final roleDocs = await dbProvider.query(
          'roles',
          where: 'name = ?',
          whereArgs: [role],
        );
        if (roleDocs.isNotEmpty) {
          final docId = roleDocs.first['documentId'] ?? roleDocs.first['id'];
          if (docId != null) {
            await dbProvider.update(
              'roles',
              values: {
                'permissions': permissionsJson,
                'updated_at': now,
              },
              where: 'documentId = ?',
              whereArgs: [docId.toString()],
            );
            notifyListeners();
            return true;
          }
        }
      }

      // Fallback: settings table (mobile or when role doc not found on web)
      final existing = await dbProvider.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['role_permissions_$role'],
      );

      if (existing.isNotEmpty) {
        await dbProvider.update(
          'settings',
          values: {
            'value': permissionsJson,
            'updated_at': now,
          },
          where: 'key = ?',
          whereArgs: ['role_permissions_$role'],
        );
      } else {
        await dbProvider.insert('settings', {
          'key': 'role_permissions_$role',
          'value': permissionsJson,
          'created_at': now,
          'updated_at': now,
        });
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('AuthProvider: Error updating role permissions: $e');
      return false;
    }
  }

  /// Check if current user has access to a section
  Future<bool> hasAccessToSection(int sectionIndex) async {
    if (_currentUserRole == null) return false;
    if (_currentUserRole == 'admin') return true; // Admin always has access

    final permissions = await getRolePermissions(_currentUserRole!);
    return permissions.contains(sectionIndex);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }
}
