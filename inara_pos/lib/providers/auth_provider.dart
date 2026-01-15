import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'unified_database_provider.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _currentUserId;
  String? _currentUserRole;
  String? _currentUsername;
  Timer? _inactivityTimer;
  BuildContext? _context;

  bool get isAuthenticated => _isAuthenticated;
  String? get currentUserId => _currentUserId;
  String? get currentUserRole => _currentUserRole;
  String? get currentUsername => _currentUsername;
  
  // Auto-lock after 5 minutes of inactivity
  static const int _inactivityTimeoutMinutes = 5;

  // Set context for accessing DatabaseProvider from Provider
  void setContext(BuildContext context) {
    _context = context;
  }

  dynamic _getDatabaseProvider() {
    if (_context != null) {
      try {
        // Use UnifiedDatabaseProvider which handles web/mobile automatically
        return Provider.of<UnifiedDatabaseProvider>(_context!, listen: false);
      } catch (e) {
        // If the stored context is no longer valid (e.g. LoginScreen disposed),
        // fall back to a fresh provider instance to avoid runtime crashes.
        debugPrint('AuthProvider: stored context no longer valid: $e');
      }
    }
    // Fallback to creating new instance (shouldn't happen in normal flow)
    return UnifiedDatabaseProvider();
  }

  Future<bool> checkPinExists() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPinInPrefs = prefs.containsKey('admin_pin');
    
    // Also check if admin user exists in database
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();
      final adminUsers = await dbProvider.query(
        'users',
        where: 'username = ? AND role = ?',
        whereArgs: ['admin', 'admin'],
      );
      
      // Return true only if both PIN in prefs AND user in database exist
      return hasPinInPrefs && adminUsers.isNotEmpty;
    } catch (e) {
      debugPrint('checkPinExists: Error checking database: $e');
      // Fallback to SharedPreferences only
      return hasPinInPrefs;
    }
  }
  
  // Force create admin user (useful for reset scenarios)
  Future<bool> forceCreateAdmin(String pin) async {
    if (pin.length < 4 || pin.length > 6) {
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

  Future<bool> setupAdminPin(String pin) async {
    if (pin.length < 4 || pin.length > 6) {
      debugPrint('SetupAdminPin: PIN length invalid: ${pin.length}');
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
          debugPrint('SetupAdminPin: Database initialization attempt ${retryCount + 1} failed: $initError');
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
        debugPrint('SetupAdminPin: Database initialization failed after retries');
        return false;
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Check if admin user already exists
      final existingUsers = await dbProvider.query(
        'users',
        where: 'username = ?',
        whereArgs: ['admin'],
      );
      debugPrint('SetupAdminPin: Existing users count: ${existingUsers.length}');
      
      if (existingUsers.isEmpty) {
        final userId = await dbProvider.insert('users', {
          'username': 'admin',
          'pin_hash': pinHash,
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
            'updated_at': now,
          },
          where: 'username = ?',
          whereArgs: ['admin'],
        );
        debugPrint('SetupAdminPin: Admin user updated. Rows affected: $rowsUpdated');
      }
      
      debugPrint('SetupAdminPin: Setup completed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error creating admin user: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> login(String username, String pin) async {
    if (pin.length < 4 || pin.length > 6) {
      debugPrint('Login: PIN length invalid: ${pin.length}');
      return false;
    }

    try {
      debugPrint('Login: Attempting login for username: $username');
      final dbProvider = _getDatabaseProvider();
      debugPrint('Login: Got database provider');
      
      // Ensure database is initialized
      await dbProvider.init();
      debugPrint('Login: Database initialized');
      
      final pinHash = _hashPin(pin);
      debugPrint('Login: PIN hashed');
      
      // First, let's check all users to debug
      final allUsers = await dbProvider.query('users');
      debugPrint('Login: Total users in database: ${allUsers.length}');
      for (var user in allUsers) {
        debugPrint('Login: Found user - username: ${user['username']}, role: ${user['role']}');
      }
      
      final users = await dbProvider.query(
        'users',
        where: 'username = ? AND pin_hash = ?',
        whereArgs: [username, pinHash],
      );
      debugPrint('Login: Query result - found ${users.length} matching users');

      if (users.isNotEmpty) {
        final user = users.first;
        // Disabled user: do not allow login
        final isActive = (user['is_active'] as num?)?.toInt();
        if (isActive != null && isActive == 0) {
          debugPrint('Login: User is disabled');
          return false;
        }
        _isAuthenticated = true;
        _currentUserId = user['id'].toString();
        _currentUserRole = user['role'] as String;
        _currentUsername = user['username'] as String;
        
        debugPrint('Login: Success! User authenticated - ID: $_currentUserId, Role: $_currentUserRole');
        _resetInactivityTimer();
        notifyListeners();
        return true;
      }
      
      debugPrint('Login: Failed - No matching user found');
      // Let's also check if username exists with different PIN
      final usernameCheck = await dbProvider.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );
      if (usernameCheck.isNotEmpty) {
        final isActive = (usernameCheck.first['is_active'] as num?)?.toInt();
        if (isActive != null && isActive == 0) {
          debugPrint('Login: Username exists but user is disabled');
          return false;
        }
        debugPrint('Login: Username exists but PIN hash does not match');
        debugPrint('Login: Expected hash: ${usernameCheck.first['pin_hash']}');
        debugPrint('Login: Provided hash: $pinHash');
      } else {
        debugPrint('Login: Username does not exist in database');
      }
      
      return false;
    } catch (e, stackTrace) {
      debugPrint('Login error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  void logout() {
    _isAuthenticated = false;
    _currentUserId = null;
    _currentUserRole = null;
    _currentUsername = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    notifyListeners();
  }

  void updateActivity() {
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
      Duration(minutes: _inactivityTimeoutMinutes),
      () {
        if (_isAuthenticated) {
          logout();
        }
      },
    );
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool get isAdmin => _currentUserRole == 'admin';
  bool get isCashier => _currentUserRole == 'cashier' || _currentUserRole == 'admin';

  // Change password for current user
  Future<bool> changePassword(String oldPin, String newPin) async {
    if (oldPin.length < 4 || oldPin.length > 6 || newPin.length < 4 || newPin.length > 6) {
      return false;
    }

    if (_currentUserId == null) {
      return false;
    }

    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      final oldPinHash = _hashPin(oldPin);
      
      // Verify old password
      final users = await dbProvider.query(
        'users',
        where: 'id = ? AND pin_hash = ?',
        whereArgs: [_currentUserId, oldPinHash],
      );

      if (users.isEmpty) {
        return false; // Old password incorrect
      }

      // Update password
      final newPinHash = _hashPin(newPin);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await dbProvider.update(
        'users',
        values: {
          'pin_hash': newPinHash,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [_currentUserId],
      );

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

  // Create new user (admin only)
  Future<bool> createUser(String username, String pin, String role) async {
    if (pin.length < 4 || pin.length > 6) {
      return false;
    }

    if (username.isEmpty || (role != 'admin' && role != 'cashier')) {
      return false;
    }

    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();

      // Check if username already exists
      final existing = await dbProvider.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );

      if (existing.isNotEmpty) {
        return false; // Username already exists
      }

      final pinHash = _hashPin(pin);
      final now = DateTime.now().millisecondsSinceEpoch;

      await dbProvider.insert('users', {
        'username': username,
        'pin_hash': pinHash,
        'role': role,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      return true;
    } catch (e) {
      debugPrint('Error creating user: $e');
      return false;
    }
  }

  // Admin-only: list users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final dbProvider = _getDatabaseProvider();
    await dbProvider.init();
    return await dbProvider.query('users', orderBy: 'username ASC');
  }

  // Admin-only: change role
  Future<bool> updateUserRole({required dynamic userId, required String role}) async {
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
  Future<bool> setUserActive({required dynamic userId, required bool isActive}) async {
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

  // Admin-only: reset PIN for another user
  Future<bool> resetUserPin({required dynamic userId, required String newPin}) async {
    if (newPin.length < 4 || newPin.length > 6) return false;
    try {
      final dbProvider = _getDatabaseProvider();
      await dbProvider.init();
      await dbProvider.update(
        'users',
        values: {'pin_hash': _hashPin(newPin)},
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [userId],
      );
      return true;
    } catch (e) {
      debugPrint('Error resetting user PIN: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }
}
