import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_provider.dart';

class SyncProvider with ChangeNotifier {
  DatabaseProvider? _dbProvider;
  bool _isSyncing = false;
  bool _isOnline = false;
  int _pendingSyncs = 0;

  DatabaseProvider get dbProvider {
    _dbProvider ??= DatabaseProvider();
    return _dbProvider!;
  }

  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  int get pendingSyncs => _pendingSyncs;

  Future<void> init() async {
    // Check connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;
    
    // Listen to connectivity changes
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      _isOnline = result != ConnectivityResult.none;
      if (_isOnline && !_isSyncing) {
        _syncPendingData();
      }
      notifyListeners();
    });

    // Start initial sync if online
    if (_isOnline) {
      _syncPendingData();
    }
  }

  Future<void> _syncPendingData() async {
    if (_isSyncing || !_isOnline) return;

    _isSyncing = true;
    notifyListeners();

    try {
      // Sync orders
      await _syncOrders();
      
      // Sync payments
      await _syncPayments();
      
      // Sync purchases
      await _syncPurchases();
      
      // Sync stock transactions
      await _syncStockTransactions();
      
      // Sync day sessions
      await _syncDaySessions();
      
      // Update pending count
      await _updatePendingCount();
      
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncOrders() async {
    final unsynced = await dbProvider.query(
      'orders',
      where: 'synced = ?',
      whereArgs: [0],
    );

    final firestore = FirebaseFirestore.instance;
    
    for (final order in unsynced) {
      try {
        await firestore.collection('orders').doc(order['id'].toString()).set({
          ...order,
          'synced_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        await dbProvider.update(
          'orders',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [order['id']],
        );
      } catch (e) {
        debugPrint('Error syncing order ${order['id']}: $e');
      }
    }
  }

  Future<void> _syncPayments() async {
    final unsynced = await dbProvider.query(
      'payments',
      where: 'synced = ?',
      whereArgs: [0],
    );

    final firestore = FirebaseFirestore.instance;
    
    for (final payment in unsynced) {
      try {
        await firestore.collection('payments').doc(payment['id'].toString()).set({
          ...payment,
          'synced_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        await dbProvider.update(
          'payments',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [payment['id']],
        );
      } catch (e) {
        debugPrint('Error syncing payment ${payment['id']}: $e');
      }
    }
  }

  Future<void> _syncPurchases() async {
    final unsynced = await dbProvider.query(
      'purchases',
      where: 'synced = ?',
      whereArgs: [0],
    );

    final firestore = FirebaseFirestore.instance;
    
    for (final purchase in unsynced) {
      try {
        await firestore.collection('purchases').doc(purchase['id'].toString()).set({
          ...purchase,
          'synced_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        await dbProvider.update(
          'purchases',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [purchase['id']],
        );
      } catch (e) {
        debugPrint('Error syncing purchase ${purchase['id']}: $e');
      }
    }
  }

  Future<void> _syncStockTransactions() async {
    final unsynced = await dbProvider.query(
      'stock_transactions',
      where: 'synced = ?',
      whereArgs: [0],
    );

    final firestore = FirebaseFirestore.instance;
    
    for (final transaction in unsynced) {
      try {
        await firestore.collection('stock_transactions').doc(transaction['id'].toString()).set({
          ...transaction,
          'synced_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        await dbProvider.update(
          'stock_transactions',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [transaction['id']],
        );
      } catch (e) {
        debugPrint('Error syncing stock transaction ${transaction['id']}: $e');
      }
    }
  }

  Future<void> _syncDaySessions() async {
    final unsynced = await dbProvider.query(
      'day_sessions',
      where: 'synced = ?',
      whereArgs: [0],
    );

    final firestore = FirebaseFirestore.instance;
    
    for (final session in unsynced) {
      try {
        await firestore.collection('day_sessions').doc(session['id'].toString()).set({
          ...session,
          'synced_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        await dbProvider.update(
          'day_sessions',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [session['id']],
        );
      } catch (e) {
        debugPrint('Error syncing day session ${session['id']}: $e');
      }
    }
  }

  Future<void> _updatePendingCount() async {
    final orders = await dbProvider.query(
      'orders',
      where: 'synced = ?',
      whereArgs: [0],
    );
    final payments = await dbProvider.query(
      'payments',
      where: 'synced = ?',
      whereArgs: [0],
    );
    final purchases = await dbProvider.query(
      'purchases',
      where: 'synced = ?',
      whereArgs: [0],
    );
    
    _pendingSyncs = orders.length + payments.length + purchases.length;
    notifyListeners();
  }

  Future<void> manualSync() async {
    await _syncPendingData();
  }
}
