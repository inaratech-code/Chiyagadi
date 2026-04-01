import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// PWA / offline UX: mirrors Firebase Auth user + ID token into local storage
/// (SharedPreferences → web: localStorage) for tooling and recovery hints.
/// Primary session remains Firebase Auth persistence; this is supplementary.
class OfflineSessionService {
  OfflineSessionService._();

  static const String sessionKey = 'chiyagadi_session';

  /// Persists uid, email, token, loginTime (matches typical PWA session JSON).
  static Future<void> persistFromUser(User user) async {
    try {
      final token = await user.getIdToken();
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'token': token,
        'loginTime': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(sessionKey, jsonEncode(payload));
      debugPrint('OfflineSessionService: session snapshot saved');
    } catch (e) {
      debugPrint('OfflineSessionService: persist failed: $e');
    }
  }

  /// Saves current [FirebaseAuth.instance.currentUser] if any (e.g. after Home opens).
  static Future<void> persistCurrentUser() async {
    if (!kIsWeb) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) await persistFromUser(u);
  }

  static Future<Map<String, dynamic>?> loadSessionJson() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(sessionKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) return map;
      return null;
    } catch (e) {
      debugPrint('OfflineSessionService: load failed: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(sessionKey);
    } catch (e) {
      debugPrint('OfflineSessionService: clear failed: $e');
    }
  }
}
