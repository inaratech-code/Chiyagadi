import 'dart:convert';

/// Role Model
/// Represents a user role with permissions
class Role {
  final dynamic id; // Can be int (SQLite) or String (Firestore)
  final String? documentId; // Firestore document ID
  final String name;
  final String? description;
  final Set<int> permissions; // Section indices (0-9)
  final bool isSystemRole; // Cannot be deleted (admin, cashier)
  final bool isActive;
  final int createdAt;
  final int updatedAt;

  Role({
    this.id,
    this.documentId,
    required this.name,
    this.description,
    required this.permissions,
    this.isSystemRole = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert Role to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (documentId != null) 'documentId': documentId,
      'name': name,
      'description': description,
      'permissions': jsonEncode(permissions.toList()),
      'is_system_role': isSystemRole ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Create Role from database map (SQLite or Firestore).
  /// Accepts permissions as JSON string or List (Firestore may return either).
  factory Role.fromMap(Map<String, dynamic> map) {
    final rawPermissions = map['permissions'];
    Set<int> permissions;
    if (rawPermissions == null) {
      permissions = {};
    } else if (rawPermissions is String) {
      try {
        final list = jsonDecode(rawPermissions);
        if (list is List) {
          permissions = list
              .map((e) => (e is num ? e : int.tryParse(e.toString()) ?? 0).toInt())
              .toSet();
        } else {
          permissions = {};
        }
      } catch (_) {
        permissions = {};
      }
    } else if (rawPermissions is List) {
      permissions = rawPermissions
          .map((e) => (e is num ? e : int.tryParse(e.toString()) ?? 0).toInt())
          .toSet();
    } else {
      permissions = {};
    }

    // SQLite uses 'id' as integer, Firestore uses documentId (or 'id' set to doc.id)
    dynamic id = map['id'];
    String? documentId = map['documentId'] as String?;
    if (documentId == null && id != null && id is String) {
      documentId = id as String;
      id = null;
    }

    final name = map['name'];
    if (name == null || name is! String) {
      throw ArgumentError('Role map must have a non-null String "name"');
    }

    return Role(
      id: id,
      documentId: documentId,
      name: name,
      description: map['description'] as String?,
      permissions: permissions,
      isSystemRole: (map['is_system_role'] as num?)?.toInt() == 1,
      isActive: (map['is_active'] as num?)?.toInt() == 1,
      createdAt: _parseTimestamp(map['created_at']),
      updatedAt: _parseTimestamp(map['updated_at']),
    );
  }

  /// Parse timestamp from num, Firestore Timestamp, or null.
  static int _parseTimestamp(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    try {
      final ms = (v as dynamic).millisecondsSinceEpoch;
      return ms is num ? ms.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Create a copy of Role with updated fields
  Role copyWith({
    dynamic id,
    String? documentId,
    String? name,
    String? description,
    Set<int>? permissions,
    bool? isSystemRole,
    bool? isActive,
    int? createdAt,
    int? updatedAt,
  }) {
    return Role(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      name: name ?? this.name,
      description: description ?? this.description,
      permissions: permissions ?? this.permissions,
      isSystemRole: isSystemRole ?? this.isSystemRole,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
