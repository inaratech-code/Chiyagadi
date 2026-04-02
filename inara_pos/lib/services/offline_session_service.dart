import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// PWA / offline UX: mirrors Firebase Auth user + ID token into local storage
/// (SharedPreferences → web: localStorage) for tooling and recovery hints.
/// Primary session remains Firebase Auth persistence; this is supplementary.
class OfflineSessionService {
  OfflineSessionService._();

  static const String sessionKey = 'chiyagadi_session';

  /// SHA-256 of email+password (salted) for offline re-login after one online sign-in.
  static const String _offlineVerifierKey = 'chiyagadi_offline_login_sha256_v1';

  static String _hashOfflineCredential(String email, String password) {
    final normalized = email.trim().toLowerCase();
    final payload = 'chiyagadi_web_offline_v1|$normalized|$password';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Call after a successful online login so the same email/password works offline.
  static Future<void> persistOfflineLoginVerifier(
      String email, String password) async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _offlineVerifierKey, _hashOfflineCredential(email, password));
    } catch (e) {
      debugPrint('OfflineSessionService: persistOfflineLoginVerifier: $e');
    }
  }

  /// Returns true if [password] matches the last saved verifier for [email].
  static Future<bool> verifyOfflineLogin(String email, String password) async {
    if (!kIsWeb) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_offlineVerifierKey);
      if (stored == null || stored.isEmpty) return false;
      return stored == _hashOfflineCredential(email, password);
    } catch (e) {
      debugPrint('OfflineSessionService: verifyOfflineLogin: $e');
      return false;
    }
  }

  /// Persists uid, email, token, loginTime (matches typical PWA session JSON).
  ///
  /// **Important:** If a full web session was already saved ([persistFullWebSession]),
  /// we **merge** and keep `userDocId`, `role`, and `username`. Otherwise
  /// [persistCurrentUser] on Home would overwrite offline login data and break
  /// [_tryOfflineCredentialLogin] / [restoreOfflineWebSession].
  static Future<void> persistFromUser(User user) async {
    try {
      String token = '';
      try {
        token = await user.getIdToken() ?? '';
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadSessionJson();
      final emailRaw = user.email ?? existing?['email'] as String?;
      final emailNorm = emailRaw?.trim().toLowerCase();
      final payload = <String, dynamic>{
        'uid': user.uid,
        if (emailNorm != null && emailNorm.isNotEmpty) 'email': emailNorm,
        'token': token,
        'loginTime': DateTime.now().millisecondsSinceEpoch,
      };
      final existingDocId = existing?['userDocId'] as String?;
      if (existingDocId != null && existingDocId.isNotEmpty) {
        payload['userDocId'] = existingDocId;
        payload['role'] = existing!['role'] ?? 'cashier';
        final un = existing['username'];
        if (un != null) payload['username'] = un;
      }
      await prefs.setString(sessionKey, jsonEncode(payload));
      debugPrint('OfflineSessionService: session snapshot saved');
    } catch (e) {
      debugPrint('OfflineSessionService: persist failed: $e');
    }
  }

  /// Web PWA: full snapshot so the app can restore role/username without Firebase when offline.
  ///
  /// [emailOverride] — use the same string you pass to [persistOfflineLoginVerifier] (Firebase
  /// canonical email). Ensures session JSON always has an email when [user.email] is null.
  static Future<void> persistFullWebSession({
    required User user,
    required String userDocId,
    required String? role,
    required String? username,
    String? emailOverride,
  }) async {
    if (!kIsWeb) return;
    try {
      // Must not fail offline restore: getIdToken() hits the network and often throws offline.
      String token = '';
      try {
        token = await user.getIdToken() ?? '';
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      final emailNorm =
          (emailOverride ?? user.email ?? '').trim().toLowerCase();
      final payload = <String, dynamic>{
        'uid': user.uid,
        if (emailNorm.isNotEmpty) 'email': emailNorm,
        'token': token,
        'loginTime': DateTime.now().millisecondsSinceEpoch,
        'userDocId': userDocId,
        'role': role ?? 'cashier',
        'username': username,
      };
      await prefs.setString(sessionKey, jsonEncode(payload));
      debugPrint('OfflineSessionService: full web session saved');
    } catch (e) {
      debugPrint('OfflineSessionService: persistFullWebSession failed: $e');
    }
  }

  /// When login succeeded without a Firebase [User] (e.g. admin fallback), still persist offline profile.
  static Future<void> persistFallbackWebProfile({
    required String userDocId,
    required String? role,
    required String? username,
    required String email,
  }) async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final emailNorm = email.trim().toLowerCase();
      final payload = <String, dynamic>{
        'uid': userDocId,
        'email': emailNorm,
        'token': '',
        'loginTime': DateTime.now().millisecondsSinceEpoch,
        'userDocId': userDocId,
        'role': role ?? 'cashier',
        'username': username,
      };
      await prefs.setString(sessionKey, jsonEncode(payload));
      debugPrint('OfflineSessionService: fallback web profile saved');
    } catch (e) {
      debugPrint('OfflineSessionService: persistFallbackWebProfile failed: $e');
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
      await prefs.remove(_offlineVerifierKey);
    } catch (e) {
      debugPrint('OfflineSessionService: clear failed: $e');
    }
  }
}
