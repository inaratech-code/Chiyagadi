import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';

import '../utils/web_navigator_online_events_stub.dart'
    if (dart.library.html) '../utils/web_navigator_online_events_web.dart' as nav_events;
import '../utils/web_online.dart';

/// Tracks online/offline for UI (banner).
///
/// **Web:** Uses [isNavigatorOnline] (`navigator.onLine`) and `online` / `offline`
/// events so the banner matches Firestore/offline routing and [registerWebOnlineSyncListener].
/// **Mobile:** Uses connectivity_plus.
class ConnectivityNotifier extends ChangeNotifier {
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  Future<void> init() async {
    if (kIsWeb) {
      _isOnline = isNavigatorOnline;
      nav_events.registerNavigatorOnlineChanged(() {
        _isOnline = isNavigatorOnline;
        notifyListeners();
      });
      notifyListeners();
      return;
    }

    try {
      final result = await Connectivity().checkConnectivity();
      _applyConnectivity(result);
    } catch (e) {
      debugPrint('ConnectivityNotifier: initial check failed: $e');
      _isOnline = true;
    }
    notifyListeners();

    Connectivity().onConnectivityChanged.listen((dynamic result) {
      _applyConnectivity(result);
      notifyListeners();
    });
  }

  void _applyConnectivity(dynamic result) {
    if (result is List<ConnectivityResult>) {
      _isOnline =
          result.isEmpty ? false : result.any((r) => r != ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      _isOnline = result != ConnectivityResult.none;
    }
  }
}
