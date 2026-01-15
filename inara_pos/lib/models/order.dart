class Order {
  final int? id;
  final String? documentId; // For Firestore string IDs
  final String orderNumber;
  final dynamic tableId; // Can be int (SQLite) or String (Firestore)
  final String orderType; // 'dine_in' or 'takeaway'
  final String status; // 'pending', 'confirmed', 'completed', 'cancelled'
  final double subtotal;
  final double discountAmount;
  final double discountPercent;
  final double taxAmount;
  final double taxPercent;
  final double totalAmount;
  final String? paymentMethod; // 'cash', 'card', 'digital'
  final String paymentStatus; // 'unpaid', 'paid', 'partial'
  final String? notes;
  final int? createdBy;
  final int createdAt;
  final int updatedAt;
  final bool synced;

  Order({
    this.id,
    this.documentId,
    required this.orderNumber,
    this.tableId,
    required this.orderType,
    this.status = 'pending',
    this.subtotal = 0,
    this.discountAmount = 0,
    this.discountPercent = 0,
    this.taxAmount = 0,
    this.taxPercent = 0,
    this.totalAmount = 0,
    this.paymentMethod,
    this.paymentStatus = 'unpaid',
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.synced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (documentId != null) 'documentId': documentId,
      'order_number': orderNumber,
      'table_id': tableId,
      'order_type': orderType,
      'status': status,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'discount_percent': discountPercent,
      'tax_amount': taxAmount,
      'tax_percent': taxPercent,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'synced': synced ? 1 : 0,
    };
  }

  factory Order.fromMap(Map<String, dynamic> map) {
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

    // Handle table_id as dynamic (int or String)
    dynamic tableIdValue;
    final tableIdData = map['table_id'];
    if (tableIdData != null) {
      if (tableIdData is int) {
        tableIdValue = tableIdData;
      } else if (tableIdData is String) {
        tableIdValue = tableIdData;
      } else if (tableIdData is num) {
        tableIdValue = tableIdData.toInt();
      }
    }

    return Order(
      id: idValue,
      documentId: docId ?? map['documentId'] as String?,
      orderNumber: map['order_number'] as String,
      tableId: tableIdValue,
      orderType: map['order_type'] as String,
      status: map['status'] as String? ?? 'pending',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0,
      taxPercent: (map['tax_percent'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: map['payment_method'] as String?,
      paymentStatus: map['payment_status'] as String? ?? 'unpaid',
      notes: map['notes'] as String?,
      createdBy: map['created_by'] as int?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      synced: (map['synced'] as int? ?? 0) == 1,
    );
  }

  Order copyWith({
    int? id,
    String? documentId,
    String? orderNumber,
    dynamic tableId,
    String? orderType,
    String? status,
    double? subtotal,
    double? discountAmount,
    double? discountPercent,
    double? taxAmount,
    double? taxPercent,
    double? totalAmount,
    String? paymentMethod,
    String? paymentStatus,
    String? notes,
    int? createdBy,
    int? createdAt,
    int? updatedAt,
    bool? synced,
  }) {
    return Order(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      orderNumber: orderNumber ?? this.orderNumber,
      tableId: tableId ?? this.tableId,
      orderType: orderType ?? this.orderType,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      discountPercent: discountPercent ?? this.discountPercent,
      taxAmount: taxAmount ?? this.taxAmount,
      taxPercent: taxPercent ?? this.taxPercent,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }
}
