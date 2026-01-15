/// Supplier Model
/// Represents a supplier/vendor in the system
class Supplier {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final int createdAt;
  final int updatedAt;

  Supplier({
    this.id,
    this.documentId,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'name': name,
      'contact_person': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    // Include documentId for Firestore if present
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    // Handle both string IDs (Firestore) and integer IDs (SQLite)
    int? idValue;
    String? docId;
    final idData = map['id'];
    if (idData != null) {
      if (idData is int) {
        idValue = idData;
      } else if (idData is String) {
        docId = idData;
        idValue = null;
      } else if (idData is num) {
        idValue = idData.toInt();
      }
    }

    return Supplier(
      id: idValue,
      documentId: docId,
      name: map['name'] as String,
      contactPerson: map['contact_person'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Supplier copyWith({
    int? id,
    String? documentId,
    String? name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool? isActive,
    int? createdAt,
    int? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
