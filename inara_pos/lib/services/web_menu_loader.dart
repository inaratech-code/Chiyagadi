import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../providers/unified_database_provider.dart';
import '../utils/web_online.dart';
import 'web_offline_first_store.dart';

/// Web-only helper aligned with React:
///
/// ```js
/// if (navigator.onLine) {
///   const snapshot = await getDocs(collection(db, "menu")); // → we use `products`
///   localStorage.setItem("menu", JSON.stringify(data));
/// } else {
///   JSON.parse(localStorage.getItem("menu")) || []
/// }
/// ```
///
/// Inara POS stores menu items in Firestore **`products`** (sellable), not a `menu` collection.
/// Successful loads are mirrored to SharedPreferences key [WebOfflineFirstStore.menuLocalStorageKey] (`"menu"`).
Future<List<Map<String, dynamic>>> loadMenuForWeb(
  UnifiedDatabaseProvider db,
) async {
  if (!kIsWeb) return [];
  await db.init();

  if (isNavigatorOnline) {
    try {
      final sellable = await db.query(
        'products',
        where: 'is_sellable = ?',
        whereArgs: [1],
      );
      if (sellable.isNotEmpty) return sellable;
      final all = await db.query('products');
      return all.where((p) {
        final v = p['is_sellable'];
        return v == null || v == 1;
      }).toList();
    } catch (e) {
      debugPrint('loadMenuForWeb: network/db failed, using menu cache: $e');
      return WebOfflineFirstStore.loadMenuFlat();
    }
  }

  return WebOfflineFirstStore.loadMenuFlat();
}
