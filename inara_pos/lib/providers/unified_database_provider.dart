import 'package:flutter/foundation.dart'
    show kIsWeb, ChangeNotifier, debugPrint;
import 'database_provider.dart';
import 'firestore_database_provider.dart';

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
      await _provider.init();
      _isInitialized = true;
      debugPrint('UnifiedDatabase: Initialized successfully');
    } catch (e) {
      debugPrint('UnifiedDatabase: Initialization failed: $e');
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

  Future<dynamic> insert(String table, Map<String, dynamic> values) async {
    if (!_isInitialized) {
      await init();
    }

    if (kIsWeb) {
      // Firestore returns String (document ID)
      return await _provider.insert(table, values);
    } else {
      // SQLite returns int
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
