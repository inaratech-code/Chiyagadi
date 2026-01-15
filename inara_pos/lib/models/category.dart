class Category {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final String name;
  final int displayOrder;
  final bool isActive;
  final bool isLocked;
  final int createdAt;
  final int updatedAt;

  Category({
    this.id,
    this.documentId,
    required this.name,
    this.displayOrder = 0,
    this.isActive = true,
    this.isLocked = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'name': name,
      'display_order': displayOrder,
      'is_active': isActive ? 1 : 0,
      'is_locked': isLocked ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    // Include documentId for Firestore if present
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    // Handle both string IDs (Firestore) and integer IDs (SQLite)
    int? idValue;
    String? docId;
    final idData = map['id'];
    if (idData != null) {
      if (idData is int) {
        idValue = idData;
      } else if (idData is String) {
        // For Firestore, store the string ID as documentId
        docId = idData;
        idValue = null; // No integer ID for Firestore
      } else if (idData is num) {
        idValue = idData.toInt();
      }
    }
    
    return Category(
      id: idValue,
      documentId: docId,
      name: map['name'] as String,
      displayOrder: (map['display_order'] as num?)?.toInt() ?? 0,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isLocked: (map['is_locked'] as int? ?? 0) == 1,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Category copyWith({
    int? id,
    String? documentId,
    String? name,
    int? displayOrder,
    bool? isActive,
    bool? isLocked,
    int? createdAt,
    int? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
