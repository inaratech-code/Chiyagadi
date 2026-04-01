import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../services/web_offline_first_store.dart';

/// Same role as Next.js `_app` `window.addEventListener("online", syncOrders)`:
/// [WebOfflineFirstStore.syncOrdersOnWebOnline] — Flutter offline `set()` queue,
/// then `pendingOrders` JSON → `orders.add()` and remove key (React interop).
void registerWebOnlineSyncListener() {
  html.window.onOnline.listen((_) async {
    try {
      if (Firebase.apps.isEmpty) return;
      await WebOfflineFirstStore.syncOrdersOnWebOnline(
        FirebaseFirestore.instance,
      );
    } catch (e) {
      debugPrint('registerWebOnlineSyncListener: $e');
    }
  });
}
