import 'package:flutter/foundation.dart' show debugPrint;
import '../providers/auth_provider.dart' show InaraAuthProvider;
import '../providers/unified_database_provider.dart';

/// Utility function to add an admin user with a specific document ID
/// Usage: Call this function from your app initialization or admin panel
Future<bool> addAdminUserWithId(
  UnifiedDatabaseProvider dbProvider,
  InaraAuthProvider authProvider,
  String documentId, {
  String username = 'admin',
  String pin = 'admin123', // Default password - user should change this
  String? email,
}) async {
  try {
    await dbProvider.init();

    debugPrint('Adding admin user with document ID: $documentId');
    debugPrint(
        'Username: $username, PIN: $pin (please change after first login)');

    final success = await authProvider.createUserWithId(
      documentId,
      username,
      pin,
      'admin',
      email: email,
    );

    if (success) {
      debugPrint('Successfully created admin user with ID: $documentId');
    } else {
      debugPrint('Failed to create admin user. User may already exist.');
    }

    return success;
  } catch (e) {
    debugPrint('Error adding admin user: $e');
    return false;
  }
}
