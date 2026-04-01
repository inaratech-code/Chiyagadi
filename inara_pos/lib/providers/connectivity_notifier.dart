import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

/// Tracks online/offline for UI (banner).
/// connectivity_plus v5+ uses [List<ConnectivityResult>] for checks and stream.
class ConnectivityNotifier extends ChangeNotifier {
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  Future<void> init() async {
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
