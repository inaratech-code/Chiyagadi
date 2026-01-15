class Customer {
  final int? id;
  final String? documentId; // For Firestore string IDs
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final double creditLimit;
  final double creditBalance;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  Customer({
    this.id,
    this.documentId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.creditLimit = 0,
    this.creditBalance = 0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (documentId != null) 'documentId': documentId,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'credit_limit': creditLimit,
      'credit_balance': creditBalance,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    // Handle both int (SQLite) and String (Firestore) IDs
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

    return Customer(
      id: idValue,
      documentId: docId ?? map['documentId'] as String?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0,
      creditBalance: (map['credit_balance'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  Customer copyWith({
    int? id,
    String? documentId,
    String? name,
    String? phone,
    String? email,
    String? address,
    double? creditLimit,
    double? creditBalance,
    String? notes,
    int? createdAt,
    int? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      creditLimit: creditLimit ?? this.creditLimit,
      creditBalance: creditBalance ?? this.creditBalance,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
