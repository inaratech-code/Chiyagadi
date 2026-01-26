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

  /// Create Role from database map
  factory Role.fromMap(Map<String, dynamic> map) {
    final permissionsJson = map['permissions'] as String? ?? '[]';
    final List<dynamic> permissionsList = jsonDecode(permissionsJson);
    final permissions = permissionsList.map((e) => (e as num).toInt()).toSet();

    // UPDATED: Better handling of ID from both SQLite and Firestore
    // SQLite uses 'id' as integer, Firestore uses 'documentId' as string
    dynamic id = map['id'];
    String? documentId = map['documentId'] as String?;
    
    // If documentId is not set but we have an id, try to use it as documentId for Firestore
    // For SQLite, id should be an integer
    if (documentId == null && id != null && id is String) {
      documentId = id as String;
      id = null; // Clear id if it's actually a documentId
    }

    return Role(
      id: id,
      documentId: documentId,
      name: map['name'] as String,
      description: map['description'] as String?,
      permissions: permissions,
      isSystemRole: (map['is_system_role'] as int?) == 1,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
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
