import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/web_local_storage_raw_stub.dart'
    if (dart.library.html) '../utils/web_local_storage_raw_web.dart' as ls;
import '../utils/web_online.dart';

/// Web-only offline-first storage: menu cache + unsynced Firestore-shaped docs.
class WebOfflineFirstStore {
  WebOfflineFirstStore._();

  static const _menuCategoriesKey = 'chiyagadi_web_menu_categories_v1';
  static const _menuProductsKey = 'chiyagadi_web_menu_products_v1';

  /// Same key as Next.js / React: `localStorage.setItem("menu", JSON.stringify(data))`.
  /// Written via [ls.webLocalStorageSet] so `localStorage.getItem("menu")` works (not only
  /// `flutter.menu` from SharedPreferences).
  static const menuLocalStorageKey = 'menu';

  /// Same key as Next.js / React:
  /// `localStorage.setItem("pendingOrders", …)` and `localStorage.getItem("pendingOrders")`
  /// ([loadPendingOrdersCompat] reads unprefixed storage first, then prefs).
  static const pendingOrdersLocalStorageKey = 'pendingOrders';
  static const _offlineDocsKey = 'chiyagadi_web_offline_docs_v1';
  static const _pendingSyncKey = 'chiyagadi_web_pending_sync_v1';

  static Future<void> cacheCategories(List<Map<String, dynamic>> rows) async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_menuCategoriesKey, jsonEncode(rows));
    } catch (e) {
      debugPrint('WebOfflineFirstStore: cacheCategories failed: $e');
    }
  }

  static Future<void> cacheProducts(List<Map<String, dynamic>> rows) async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(rows);
      await prefs.setString(_menuProductsKey, encoded);
      await prefs.setString(menuLocalStorageKey, encoded);
      ls.webLocalStorageSet(menuLocalStorageKey, encoded);
    } catch (e) {
      debugPrint('WebOfflineFirstStore: cacheProducts failed: $e');
    }
  }

  /// Read only the flat `menu` key (React/Next interop). Empty if missing/invalid.
  static Future<List<Map<String, dynamic>>> loadMenuFlat() async {
    if (!kIsWeb) return [];
    try {
      var raw = ls.webLocalStorageGet(menuLocalStorageKey);
      if (raw == null || raw.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(menuLocalStorageKey);
      }
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: loadMenuFlat: $e');
      return [];
    }
  }

  static Future<bool> hasMenuCache() async {
    if (!kIsWeb) return false;
    try {
      final flat = ls.webLocalStorageGet(menuLocalStorageKey);
      if (flat != null && flat.isNotEmpty) return true;
      final prefs = await SharedPreferences.getInstance();
      final c = prefs.getString(_menuCategoriesKey);
      final p = prefs.getString(_menuProductsKey);
      return (c != null && c.isNotEmpty) || (p != null && p.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> loadCachedCategories() async {
    if (!kIsWeb) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_menuCategoriesKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: loadCachedCategories: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> loadCachedProducts() async {
    if (!kIsWeb) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_menuProductsKey);
      if (raw == null || raw.isEmpty) {
        raw = ls.webLocalStorageGet(menuLocalStorageKey);
      }
      if (raw == null || raw.isEmpty) {
        raw = prefs.getString(menuLocalStorageKey);
      }
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: loadCachedProducts: $e');
      return [];
    }
  }

  static const _ordersReadCacheKey = 'chiyagadi_web_orders_read_cache_v1';
  static const int _ordersReadCacheMax = 500;

  /// Order document IDs removed while offline (so they stay hidden after cache merges).
  static const _deletedOrderIdsKey = 'chiyagadi_web_deleted_order_ids_v1';
  static const int _deletedOrderIdsMax = 500;

  /// Stable Firestore/local id for an order row (handles documentId vs id vs document_id).
  static String? orderRowDocumentId(Map<String, dynamic> r) {
    final v = r['documentId'] ?? r['id'] ?? r['document_id'];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static const _customersReadCacheKey = 'chiyagadi_web_customers_read_cache_v1';
  static const int _customersReadCacheMax = 500;

  /// Merges server `orders` rows into local cache so [firestoreLikeQuery] can list recent
  /// history while offline (e.g. today's orders after at least one online load).
  static Future<void> mergeOrdersIntoReadCache(List<Map<String, dynamic>> rows) async {
    if (!kIsWeb || rows.isEmpty) return;
    try {
      final tomb = await _loadDeletedOrderIds();
      final byId = <String, Map<String, dynamic>>{};
      for (final r in await loadOrdersReadCache()) {
        final id = orderRowDocumentId(r);
        if (id != null && !tomb.contains(id)) {
          byId[id] = Map<String, dynamic>.from(r);
        }
      }
      for (final r in rows) {
        final id = orderRowDocumentId(r);
        if (id == null || tomb.contains(id)) continue;
        byId[id] = Map<String, dynamic>.from(r);
      }
      var list = byId.values.toList();
      list.sort((a, b) {
        final ta = (a['created_at'] as num?)?.toInt() ?? 0;
        final tb = (b['created_at'] as num?)?.toInt() ?? 0;
        return tb.compareTo(ta);
      });
      if (list.length > _ordersReadCacheMax) {
        list = list.take(_ordersReadCacheMax).toList();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ordersReadCacheKey, jsonEncode(list));
    } catch (e) {
      debugPrint('WebOfflineFirstStore: mergeOrdersIntoReadCache: $e');
    }
  }

  /// Replaces the `orders` read cache with the latest online query result.
  ///
  /// This prevents "ghost" orders from reappearing offline after they were deleted online
  /// (because a merge would keep older cached rows that no longer exist server-side).
  static Future<void> replaceOrdersReadCache(List<Map<String, dynamic>> rows) async {
    if (!kIsWeb) return;
    try {
      final tomb = await _loadDeletedOrderIds();
      final byId = <String, Map<String, dynamic>>{};
      for (final r in rows) {
        final id = orderRowDocumentId(r);
        if (id == null || tomb.contains(id)) continue;
        byId[id] = Map<String, dynamic>.from(r);
      }
      var list = byId.values.toList();
      list.sort((a, b) {
        final ta = (a['created_at'] as num?)?.toInt() ?? 0;
        final tb = (b['created_at'] as num?)?.toInt() ?? 0;
        return tb.compareTo(ta);
      });
      if (list.length > _ordersReadCacheMax) {
        list = list.take(_ordersReadCacheMax).toList();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ordersReadCacheKey, jsonEncode(list));
    } catch (e) {
      debugPrint('WebOfflineFirstStore: replaceOrdersReadCache: $e');
    }
  }

  /// Cached order rows from last successful online queries (newest first).
  /// Drops tombstoned ids and persists the compacted list so merges cannot resurrect ghosts.
  static Future<List<Map<String, dynamic>>> loadOrdersReadCache() async {
    if (!kIsWeb) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_ordersReadCacheKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      var rows =
          list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final tomb = await _loadDeletedOrderIds();
      if (tomb.isEmpty) return rows;
      final filtered = rows.where((r) {
        final id = orderRowDocumentId(r);
        return id == null || !tomb.contains(id);
      }).toList();
      if (filtered.length < rows.length) {
        await prefs.setString(_ordersReadCacheKey, jsonEncode(filtered));
        debugPrint(
            'WebOfflineFirstStore: loadOrdersReadCache removed ${rows.length - filtered.length} tombstoned row(s)');
      }
      return filtered;
    } catch (e) {
      debugPrint('WebOfflineFirstStore: loadOrdersReadCache: $e');
      return [];
    }
  }

  static Future<Set<String>> _loadDeletedOrderIds() async {
    if (!kIsWeb) return {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_deletedOrderIdsKey);
      if (raw == null || raw.isEmpty) return {};
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: _loadDeletedOrderIds: $e');
      return {};
    }
  }

  /// Remember an order removed offline so [firestoreLikeQuery] does not show it again after merges.
  static Future<void> rememberDeletedOrderId(String documentId) async {
    final id = documentId.trim();
    if (!kIsWeb || id.isEmpty) return;
    try {
      final set = await _loadDeletedOrderIds();
      set.add(id);
      var list = set.toList();
      if (list.length > _deletedOrderIdsMax) {
        list = list.sublist(list.length - _deletedOrderIdsMax);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deletedOrderIdsKey, jsonEncode(list));
    } catch (e) {
      debugPrint('WebOfflineFirstStore: rememberDeletedOrderId: $e');
    }
  }

  /// Drops one order row from the read cache by [documentId]. Returns true if a row was removed.
  static Future<bool> removeOrderFromReadCache(String documentId) async {
    final target = documentId.trim();
    if (!kIsWeb || target.isEmpty) return false;
    try {
      final rows = await loadOrdersReadCache();
      final next = rows
          .where((r) => orderRowDocumentId(r) != target)
          .toList();
      if (next.length == rows.length) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ordersReadCacheKey, jsonEncode(next));
      return true;
    } catch (e) {
      debugPrint('WebOfflineFirstStore: removeOrderFromReadCache: $e');
      return false;
    }
  }

  /// Call after an order is successfully deleted on Firestore while online. Without this,
  /// [loadOrdersReadCache] can still contain the order, so it reappears when the app goes offline.
  static Future<void> applyOrderDeletionToLocalCache(String documentId) async {
    final id = documentId.trim();
    if (!kIsWeb || id.isEmpty) return;
    try {
      await removeOrderFromReadCache(id);
      await rememberDeletedOrderId(id);
      await _removePendingOrdersWithDocumentId(id);
      final coll = await _loadCollectionMap('orders');
      var collChanged = false;
      if (coll.remove(id) != null) {
        collChanged = true;
      }
      final orphanKeys = coll.entries
          .where((e) => orderRowDocumentId(e.value) == id)
          .map((e) => e.key)
          .toList();
      for (final k in orphanKeys) {
        coll.remove(k);
        collChanged = true;
      }
      if (collChanged) {
        await _persistCollectionMap('orders', coll);
      }
      await _removePending('orders', id);
    } catch (e) {
      debugPrint('WebOfflineFirstStore: applyOrderDeletionToLocalCache: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> _filterOutDeletedOrders(
    List<Map<String, dynamic>> rows,
  ) async {
    final tomb = await _loadDeletedOrderIds();
    if (tomb.isEmpty) return rows;
    return rows.where((r) {
      final id = orderRowDocumentId(r);
      return id == null || !tomb.contains(id);
    }).toList();
  }

  /// Last successful online `customers` queries (for offline payment / credit updates).
  static Future<void> mergeCustomersIntoReadCache(
      List<Map<String, dynamic>> rows) async {
    if (!kIsWeb || rows.isEmpty) return;
    try {
      final byId = <String, Map<String, dynamic>>{};
      for (final r in await loadCustomersReadCache()) {
        final id = (r['documentId'] ?? r['id'])?.toString();
        if (id != null && id.isNotEmpty) {
          byId[id] = Map<String, dynamic>.from(r);
        }
      }
      for (final r in rows) {
        final id = (r['documentId'] ?? r['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        byId[id] = Map<String, dynamic>.from(r);
      }
      var list = byId.values.toList();
      list.sort((a, b) {
        final ta = (a['updated_at'] as num?)?.toInt() ??
            (a['created_at'] as num?)?.toInt() ??
            0;
        final tb = (b['updated_at'] as num?)?.toInt() ??
            (b['created_at'] as num?)?.toInt() ??
            0;
        return tb.compareTo(ta);
      });
      if (list.length > _customersReadCacheMax) {
        list = list.take(_customersReadCacheMax).toList();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customersReadCacheKey, jsonEncode(list));
    } catch (e) {
      debugPrint('WebOfflineFirstStore: mergeCustomersIntoReadCache: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> loadCustomersReadCache() async {
    if (!kIsWeb) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customersReadCacheKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: loadCustomersReadCache: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> _findOrderInReadCache(String id) async {
    final needle = id.trim();
    for (final r in await loadOrdersReadCache()) {
      if (orderRowDocumentId(r) == needle) {
        return Map<String, dynamic>.from(r);
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _findCustomerInReadCache(String id) async {
    for (final r in await loadCustomersReadCache()) {
      if ((r['documentId'] ?? r['id'])?.toString() == id) {
        return Map<String, dynamic>.from(r);
      }
    }
    return null;
  }

  static Future<Map<String, Map<String, dynamic>>> _loadCollectionMap(
      String collection) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineDocsKey);
    if (raw == null || raw.isEmpty) return {};
    final outer = jsonDecode(raw) as Map<String, dynamic>;
    final coll = outer[collection];
    if (coll is! Map) return {};
    return coll.map(
      (k, v) => MapEntry(
        k.toString(),
        Map<String, dynamic>.from(v as Map),
      ),
    );
  }

  static Future<void> _persistCollectionMap(
    String collection,
    Map<String, Map<String, dynamic>> docs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_offlineDocsKey);
    final outer = raw != null && raw.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : <String, dynamic>{};
    outer[collection] = docs;
    await prefs.setString(_offlineDocsKey, jsonEncode(outer));
  }

  static Future<List<Map<String, dynamic>>> _pendingList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingSyncKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      // Backward compatible: older entries were {collection,id}. New entries add {op}.
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['op'] = (m['op']?.toString().trim().isNotEmpty ?? false)
            ? m['op'].toString().trim()
            : 'set';
        return m;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _setPendingList(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await prefs.remove(_pendingSyncKey);
    } else {
      await prefs.setString(_pendingSyncKey, jsonEncode(list));
    }
  }

  static Future<void> _addPending(
    String collection,
    String id, {
    String op = 'set', // 'set' or 'delete'
  }) async {
    final list = await _pendingList();
    final normalizedOp = op.trim().isEmpty ? 'set' : op.trim();
    final key = '$collection::$id::$normalizedOp';
    final exists = list.any(
        (m) => '${m['collection']}::${m['id']}::${m['op']}' == key);
    if (!exists) {
      list.add({'collection': collection, 'id': id, 'op': normalizedOp});
      await _setPendingList(list);
    }
  }

  /// Merges docs that were written offline and not yet synced into server [rows].
  static Future<List<Map<String, dynamic>>> mergePendingIntoQueryResult(
    String collection,
    List<Map<String, dynamic>> serverRows,
  ) async {
    if (!kIsWeb) return serverRows;
    final pending = await _pendingList();
    final ids = pending
        .where((m) =>
            m['collection'] == collection && (m['op']?.toString() ?? 'set') == 'set')
        .map((m) => m['id'] as String?)
        .whereType<String>()
        .toSet();
    if (ids.isEmpty) return serverRows;

    final byId = <String, Map<String, dynamic>>{};
    for (final r in serverRows) {
      final id = (r['documentId'] ?? r['id'])?.toString();
      if (id != null) byId[id] = r;
    }

    final coll = await _loadCollectionMap(collection);
    final out = List<Map<String, dynamic>>.from(serverRows);
    for (final id in ids) {
      if (byId.containsKey(id)) continue;
      final doc = coll[id];
      if (doc != null) out.add(Map<String, dynamic>.from(doc));
    }
    return out;
  }

  /// [reactPendingDueToErrorFallback] matches JS `catch`: push plain `order` to `pendingOrders`.
  /// Default `false` matches offline branch: `{ ...order, offline: true, createdAt }`.
  static Future<String> insertDocument(
    String collection,
    Map<String, dynamic> data, {
    String? documentId,
    bool reactPendingDueToErrorFallback = false,
  }) async {
    final id = documentId ?? const Uuid().v4();
    final copy = Map<String, dynamic>.from(data);
    copy.remove('id');
    copy['documentId'] = id;
    copy['id'] = id;

    final coll = await _loadCollectionMap(collection);
    coll[id] = copy;
    await _persistCollectionMap(collection, coll);
    await _addPending(collection, id, op: 'set');
    debugPrint('WebOfflineFirstStore: offline insert $collection/$id');

    if (kIsWeb && collection == 'orders') {
      await _appendPendingOrderReactCompat(
        Map<String, dynamic>.from(copy),
        dueToErrorFallback: reactPendingDueToErrorFallback,
      );
    }

    return id;
  }

  static Future<List<Map<String, dynamic>>> _loadPendingOrdersRawList() async {
    try {
      var raw = ls.webLocalStorageGet(pendingOrdersLocalStorageKey);
      if (raw == null || raw.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(pendingOrdersLocalStorageKey);
      }
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: _loadPendingOrdersRawList: $e');
      return [];
    }
  }

  static Future<void> _savePendingOrdersRawList(
      List<Map<String, dynamic>> list) async {
    final encoded = jsonEncode(list);
    ls.webLocalStorageSet(pendingOrdersLocalStorageKey, encoded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingOrdersLocalStorageKey, encoded);
  }

  /// Mirrors JS `createOrder` offline / catch `pendingOrders` queue (unprefixed localStorage).
  static Future<void> _appendPendingOrderReactCompat(
    Map<String, dynamic> orderDoc, {
    required bool dueToErrorFallback,
  }) async {
    try {
      final list = await _loadPendingOrdersRawList();
      final entry = Map<String, dynamic>.from(orderDoc);
      if (!dueToErrorFallback) {
        entry['offline'] = true;
        entry['createdAt'] = DateTime.now().millisecondsSinceEpoch;
      }
      list.add(entry);
      await _savePendingOrdersRawList(list);
    } catch (e) {
      debugPrint('WebOfflineFirstStore: _appendPendingOrderReactCompat: $e');
    }
  }

  static Future<void> _removePendingOrdersWithDocumentId(String documentId) async {
    try {
      final list = await _loadPendingOrdersRawList();
      final filtered = list.where((m) {
        final mid =
            m['documentId']?.toString() ?? m['id']?.toString();
        return mid != documentId;
      }).toList();
      if (filtered.length == list.length) return;
      await _savePendingOrdersRawList(filtered);
    } catch (e) {
      debugPrint('WebOfflineFirstStore: _removePendingOrdersWithDocumentId: $e');
    }
  }

  static Future<int> updateDocument(
    String collection, {
    required Map<String, dynamic> data,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (where == null || whereArgs == null || whereArgs.isEmpty) return 0;

    if (where.contains('documentId = ?') && whereArgs.isNotEmpty) {
      final id = whereArgs.first.toString();
      final coll = await _loadCollectionMap(collection);
      Map<String, dynamic>? existing = coll[id];
      if (existing == null && collection == 'orders') {
        existing = await _findOrderInReadCache(id);
      } else if (existing == null && collection == 'customers') {
        existing = await _findCustomerInReadCache(id);
      }
      if (existing == null) return 0;
      final merged = Map<String, dynamic>.from(existing);
      merged.addAll(data);
      merged['updated_at'] =
          data['updated_at'] ?? DateTime.now().millisecondsSinceEpoch;
      coll[id] = merged;
      await _persistCollectionMap(collection, coll);
      await _addPending(collection, id, op: 'set');
      if (collection == 'orders') {
        await mergeOrdersIntoReadCache([merged]);
      } else if (collection == 'customers') {
        await mergeCustomersIntoReadCache([merged]);
      }
      return 1;
    }

    final docs = await _loadCollectionMap(collection);
    var count = 0;
    for (final entry in docs.entries) {
      if (_matchesWhereClause(entry.value, where, whereArgs)) {
        final merged = Map<String, dynamic>.from(entry.value);
        merged.addAll(data);
        merged['updated_at'] =
            data['updated_at'] ?? DateTime.now().millisecondsSinceEpoch;
        docs[entry.key] = merged;
        count++;
        await _addPending(collection, entry.key, op: 'set');
      }
    }
    if (count > 0) await _persistCollectionMap(collection, docs);
    return count;
  }

  static Future<int> deleteDocument(
    String collection, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (where == null || whereArgs == null || whereArgs.isEmpty) return 0;

    final wTrim = where.trim();
    if (wTrim == 'order_id = ?') {
      final oid = whereArgs.first.toString();
      final docs = await _loadCollectionMap(collection);
      final keysToRemove = <String>[];
      for (final e in docs.entries) {
        final rowOrderId =
            e.value['order_id']?.toString() ?? e.value['orderId']?.toString();
        if (rowOrderId == oid) keysToRemove.add(e.key);
      }
      var count = 0;
      for (final k in keysToRemove) {
        docs.remove(k);
        await _removePending(collection, k);
        count++;
      }
      if (count > 0) await _persistCollectionMap(collection, docs);
      return count;
    }

    if (where.contains('documentId = ?') && whereArgs.isNotEmpty) {
      final id = whereArgs.first.toString();
      final coll = await _loadCollectionMap(collection);
      var removedFromMap = false;
      if (coll.containsKey(id)) {
        coll.remove(id);
        await _persistCollectionMap(collection, coll);
        removedFromMap = true;
      }
      // Queue a server-side delete for when we're back online.
      await _addPending(collection, id, op: 'delete');

      if (collection == 'orders') {
        await removeOrderFromReadCache(id);
        await rememberDeletedOrderId(id);
        await _removePendingOrdersWithDocumentId(id);
        return 1;
      }
      return removedFromMap ? 1 : 0;
    }
    return 0;
  }

  static Future<void> _removePending(String collection, String id) async {
    final list = await _pendingList();
    list.removeWhere(
      (m) => m['collection'] == collection && m['id'] == id,
    );
    await _setPendingList(list);
  }

  /// React/Next interop: read `pendingOrders` (raw localStorage first, then prefs).
  static Future<List<Map<String, dynamic>>> loadPendingOrdersCompat() async {
    if (!kIsWeb) return [];
    try {
      return await _loadPendingOrdersRawList();
    } catch (e) {
      debugPrint('WebOfflineFirstStore: loadPendingOrdersCompat: $e');
      return [];
    }
  }

  static bool _matchesWhereClause(
    Map<String, dynamic> row,
    String where,
    List<Object?> whereArgs,
  ) {
    final conditions = where.split(' AND ');
    var argIndex = 0;
    for (final condition in conditions) {
      final c = condition.trim();
      if (argIndex >= whereArgs.length) return false;

      if (c.contains(' >= ?')) {
        final field = c.split(' >= ?')[0].trim();
        final v = whereArgs[argIndex];
        final fv = _fieldValue(row, field);
        if (!_compareNum(fv, v, (a, b) => a >= b)) return false;
        argIndex++;
      } else if (c.contains(' <= ?')) {
        final field = c.split(' <= ?')[0].trim();
        final v = whereArgs[argIndex];
        final fv = _fieldValue(row, field);
        if (!_compareNum(fv, v, (a, b) => a <= b)) return false;
        argIndex++;
      } else if (c.contains(' LIKE ?')) {
        final field = c.split(' LIKE ?')[0].trim();
        final pattern = whereArgs[argIndex]?.toString() ?? '';
        final fv = _fieldValue(row, field)?.toString() ?? '';
        if (!_sqlLikeMatch(fv, pattern)) return false;
        argIndex++;
      } else if (c.contains(' = ?')) {
        final field = c.split(' = ?')[0].trim();
        final v = whereArgs[argIndex];
        final fv = _fieldValue(row, field);
        if (!_sqlFieldEquals(field, fv, v)) {
          return false;
        }
        argIndex++;
      } else {
        return false;
      }
    }
    return true;
  }

  /// Firestore/cache rows use `true`/`false`; queries use `1`/`0` (SQLite style).
  static bool _sqlFieldEquals(String? field, dynamic fv, dynamic v) {
    if (field == 'is_sellable' && (v == 1 || v == '1')) {
      if (fv == null) return true;
    }
    return _sqlValueEquals(fv, v);
  }

  static bool _sqlValueEquals(dynamic fv, dynamic v) {
    if (fv == v) return true;
    if (fv == null && v == null) return true;
    bool? asBool(dynamic x) {
      if (x == null) return null;
      if (x is bool) return x;
      if (x is num) return x != 0;
      final s = x.toString().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return null;
    }

    final fb = asBool(fv);
    final ab = asBool(v);
    if (fb != null && ab != null) return fb == ab;
    return fv?.toString() == v?.toString();
  }

  static bool _compareNum(
    dynamic fv,
    dynamic v,
    bool Function(double a, double b) cmp,
  ) {
    final a = (fv is num) ? fv.toDouble() : double.tryParse(fv?.toString() ?? '');
    final b = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (a == null || b == null) return false;
    return cmp(a, b);
  }

  /// Minimal SQL LIKE for Firestore-style patterns (e.g. `ORD 260401/%`).
  static bool _sqlLikeMatch(String value, String pattern) {
    if (!pattern.contains('%')) {
      return value == pattern;
    }
    final esc = pattern.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');
    final re = '^${esc.replaceAll('%', '.*')}\$';
    try {
      return RegExp(re).hasMatch(value);
    } catch (_) {
      return value.startsWith(pattern.replaceAll('%', ''));
    }
  }

  static dynamic _fieldValue(Map<String, dynamic> row, String field) {
    if (field == 'documentId' || field == 'id') {
      return row['documentId'] ?? row['id'];
    }
    return row[field];
  }

  /// Offline Firestore-like query (navigator offline).
  static Future<List<Map<String, dynamic>>> firestoreLikeQuery({
    required String collection,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (where != null &&
        whereArgs != null &&
        whereArgs.length == 1 &&
        (where.trim() == 'documentId = ?' || where.trim() == 'id = ?') &&
        whereArgs.first is String) {
      final id = whereArgs.first as String;
      if (collection == 'categories' || collection == 'products') {
        final all = collection == 'categories'
            ? await loadCachedCategories()
            : await loadCachedProducts();
        for (final r in all) {
          if ((r['documentId'] ?? r['id'])?.toString() == id) {
            return [Map<String, dynamic>.from(r)];
          }
        }
        return [];
      }
      if (collection == 'orders') {
        final tomb = await _loadDeletedOrderIds();
        if (tomb.contains(id)) return [];
        final coll = await _loadCollectionMap(collection);
        final offline = coll[id];
        if (offline != null) return [Map<String, dynamic>.from(offline)];
        for (final r in await loadOrdersReadCache()) {
          if (orderRowDocumentId(r) == id) {
            return [Map<String, dynamic>.from(r)];
          }
        }
        return [];
      }
      if (collection == 'customers') {
        final coll = await _loadCollectionMap(collection);
        final offline = coll[id];
        if (offline != null) return [Map<String, dynamic>.from(offline)];
        for (final r in await loadCustomersReadCache()) {
          if ((r['documentId'] ?? r['id'])?.toString() == id) {
            return [Map<String, dynamic>.from(r)];
          }
        }
        return [];
      }
      final coll = await _loadCollectionMap(collection);
      final doc = coll[id];
      if (doc == null) return [];
      return [Map<String, dynamic>.from(doc)];
    }

    List<Map<String, dynamic>> base;
    if (collection == 'categories') {
      base = await loadCachedCategories();
    } else if (collection == 'products') {
      base = await loadCachedProducts();
    } else if (collection == 'orders') {
      final tomb = await _loadDeletedOrderIds();
      final byId = <String, Map<String, dynamic>>{};
      for (final r in await loadOrdersReadCache()) {
        final oid = orderRowDocumentId(r);
        if (oid != null && !tomb.contains(oid)) {
          byId[oid] = Map<String, dynamic>.from(r);
        }
      }
      final m = await _loadCollectionMap('orders');
      for (final e in m.entries) {
        if (tomb.contains(e.key)) continue;
        final rowId = orderRowDocumentId(e.value) ?? e.key;
        if (tomb.contains(rowId)) continue;
        byId[rowId] = Map<String, dynamic>.from(e.value);
      }
      base = await _filterOutDeletedOrders(byId.values.toList());
    } else if (collection == 'customers') {
      final byId = <String, Map<String, dynamic>>{};
      for (final r in await loadCustomersReadCache()) {
        final cid = (r['documentId'] ?? r['id'])?.toString();
        if (cid != null && cid.isNotEmpty) {
          byId[cid] = Map<String, dynamic>.from(r);
        }
      }
      final m = await _loadCollectionMap('customers');
      for (final e in m.entries) {
        byId[e.key] = Map<String, dynamic>.from(e.value);
      }
      base = byId.values.toList();
    } else {
      final m = await _loadCollectionMap(collection);
      base = m.values.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    var rows = _applyWhere(base, where, whereArgs);
    if (orderBy != null) {
      _sortRowsInMemory(rows, orderBy);
    }
    var start = (offset ?? 0).clamp(0, rows.length);
    var out = rows.skip(start);
    if (limit != null) {
      out = out.take(limit);
    }
    return out.toList();
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
      return compareDynamic(ra['id'], rb['id']);
    });
  }

  static List<Map<String, dynamic>> _applyWhere(
    List<Map<String, dynamic>> rows,
    String? where,
    List<Object?>? whereArgs,
  ) {
    if (where == null || whereArgs == null || whereArgs.isEmpty) {
      return List<Map<String, dynamic>>.from(rows);
    }
    if (where.toUpperCase().contains(' IN (')) {
      return _applyWhereIn(rows, where, whereArgs);
    }
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (_matchesWhereClause(row, where, whereArgs)) {
        out.add(row);
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _applyWhereIn(
    List<Map<String, dynamic>> rows,
    String where,
    List<Object?> whereArgs,
  ) {
    final inRe = RegExp(r'^(\w+)\s+IN\s*\(([^)]*)\)$', caseSensitive: false);
    final conditions = where.split(' AND ').map((s) => s.trim()).toList();
    String? inField;
    List<Object?> inValues = const [];
    final other = <MapEntry<String, Object?>>[];
    var argIndex = 0;

    for (final cond in conditions) {
      final m = inRe.firstMatch(cond);
      if (m != null) {
        final placeholderCount = RegExp(r'\?').allMatches(m.group(2) ?? '').length;
        inField = (m.group(1) ?? '').trim();
        final end = (argIndex + placeholderCount).clamp(0, whereArgs.length);
        inValues = whereArgs.sublist(argIndex, end);
        argIndex = end;
        continue;
      }
      if (cond.contains(' = ?')) {
        final field = cond.split(' = ?')[0].trim();
        if (argIndex < whereArgs.length) {
          other.add(MapEntry(field, whereArgs[argIndex]));
          argIndex++;
        }
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      var ok = true;
      for (final e in other) {
        if (!_sqlFieldEquals(e.key, _fieldValue(row, e.key), e.value)) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      if (inField != null && inValues.isNotEmpty) {
        final fv = _fieldValue(row, inField);
        if (!inValues.any((v) => _sqlFieldEquals(inField, fv, v))) {
          continue;
        }
      }
      out.add(row);
    }
    return out;
  }

  /// Push Flutter offline writes to Firestore with `set(docId, …)` (stable ids).
  static Future<void> syncPendingToFirestore(FirebaseFirestore fs) async {
    if (!kIsWeb || isNavigatorOnline == false) return;

    final pending = await _pendingList();
    if (pending.isEmpty) return;

    for (final p in List<Map<String, dynamic>>.from(pending)) {
      final collection = p['collection'] as String?;
      final id = p['id'] as String?;
      final op = (p['op']?.toString().trim().isNotEmpty ?? false)
          ? p['op'].toString().trim()
          : 'set';
      if (collection == null || id == null) continue;

      try {
        if (op == 'delete') {
          await fs.collection(collection).doc(id).delete();
          await _removePending(collection, id);
          if (collection == 'orders') {
            await _removePendingOrdersWithDocumentId(id);
          }
          // Ensure local caches are consistent post-sync.
          if (collection == 'orders') {
            await applyOrderDeletionToLocalCache(id);
          }
          debugPrint('WebOfflineFirstStore: synced delete $collection/$id');
          continue;
        }

        final coll = await _loadCollectionMap(collection);
        final doc = coll[id];
        if (doc == null) {
          await _removePending(collection, id);
          continue;
        }
        final payload = Map<String, dynamic>.from(doc);
        payload.remove('id');
        payload.remove('documentId');
        await fs.collection(collection).doc(id).set(payload);
        await _removePending(collection, id);
        // Flutter orders were also mirrored into pendingOrders JSON; remove so the React
        // flush below does not add() a duplicate document.
        if (collection == 'orders') {
          await _removePendingOrdersWithDocumentId(id);
        }
        coll.remove(id);
        await _persistCollectionMap(collection, coll);
        debugPrint('WebOfflineFirstStore: synced $collection/$id');
      } catch (e) {
        debugPrint('WebOfflineFirstStore: sync failed for $collection/$id: $e');
      }
    }
  }

  /// React `_app.js` equivalent: `window.addEventListener("online", syncOrders)` then
  /// `localStorage.removeItem("pendingOrders")` after uploads.
  ///
  /// 1. [syncPendingToFirestore] — `set()` with stable ids (Flutter offline queue).
  /// 2. If internal queue is empty but `pendingOrders` still has rows (e.g. Next.js-only
  ///    offline writes), `add()` each like `addDoc(collection(db, "orders"), order)`.
  /// 3. Clear [pendingOrdersLocalStorageKey] when safe.
  static Future<void> syncOrdersOnWebOnline(FirebaseFirestore fs) async {
    if (!kIsWeb || !isNavigatorOnline) return;
    await syncPendingToFirestore(fs);

    final stillPending = await _pendingList();
    if (stillPending.isNotEmpty) {
      return;
    }

    final reactStyle = await loadPendingOrdersCompat();
    if (reactStyle.isEmpty) return;

    for (final order in reactStyle) {
      try {
        final copy = Map<String, dynamic>.from(order);
        copy.remove('id');
        copy.remove('documentId');
        copy.remove('offline');
        copy.remove('createdAt');
        await fs.collection('orders').add(copy);
      } catch (e) {
        debugPrint('WebOfflineFirstStore: add() pending order (react-style): $e');
      }
    }
    try {
      ls.webLocalStorageRemove(pendingOrdersLocalStorageKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(pendingOrdersLocalStorageKey);
    } catch (e) {
      debugPrint('WebOfflineFirstStore: remove pendingOrders key: $e');
    }
  }
}
