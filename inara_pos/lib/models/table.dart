class CafeTable {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final String tableNumber;
  final int capacity;
  final String status; // 'available' or 'occupied'
  final int? rowPosition;
  final int? columnPosition;
  final String? positionLabel;
  final String? notes;
  final int createdAt;
  final int updatedAt;

  CafeTable({
    this.id,
    this.documentId,
    required this.tableNumber,
    this.capacity = 4,
    this.status = 'available',
    this.rowPosition,
    this.columnPosition,
    this.positionLabel,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_number': tableNumber,
      'capacity': capacity,
      'status': status,
      'row_position': rowPosition,
      'column_position': columnPosition,
      'position_label': positionLabel,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory CafeTable.fromMap(Map<String, dynamic> map) {
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

    return CafeTable(
      id: idValue,
      documentId: docId,
      tableNumber: map['table_number'] as String? ?? '',
      capacity: (map['capacity'] as num?)?.toInt() ?? 4,
      status: map['status'] as String? ?? 'available',
      rowPosition: (map['row_position'] as num?)?.toInt(),
      columnPosition: (map['column_position'] as num?)?.toInt(),
      positionLabel: map['position_label'] as String?,
      notes: map['notes'] as String?,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  CafeTable copyWith({
    int? id,
    String? documentId,
    String? tableNumber,
    int? capacity,
    String? status,
    int? rowPosition,
    int? columnPosition,
    String? positionLabel,
    String? notes,
    int? createdAt,
    int? updatedAt,
  }) {
    return CafeTable(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      tableNumber: tableNumber ?? this.tableNumber,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      rowPosition: rowPosition ?? this.rowPosition,
      columnPosition: columnPosition ?? this.columnPosition,
      positionLabel: positionLabel ?? this.positionLabel,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
