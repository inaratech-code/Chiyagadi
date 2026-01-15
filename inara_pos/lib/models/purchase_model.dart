/// Purchase Model
/// Represents a purchase order from a supplier
class Purchase {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final dynamic supplierId; // Can be int (SQLite) or String (Firestore)
  final String? supplierName; // Denormalized for display
  final String purchaseNumber; // Unique purchase number (e.g., PUR-20240101-001)
  final double totalAmount;
  final double? discountAmount;
  final double? taxAmount;
  final double paidAmount; // Amount paid so far
  final double? outstandingAmount; // Remaining amount to pay (nullable, calculated if not provided)
  final String paymentStatus; // 'unpaid', 'partial', 'paid'
  final String? notes;
  final String status; // 'pending', 'completed', 'cancelled'
  final int? createdBy;
  final int createdAt;
  final int updatedAt;

  Purchase({
    this.id,
    this.documentId,
    required this.supplierId,
    this.supplierName,
    required this.purchaseNumber,
    required this.totalAmount,
    this.discountAmount,
    this.taxAmount,
    this.paidAmount = 0.0,
    this.outstandingAmount, // Can be null, will be calculated if not provided
    this.paymentStatus = 'unpaid',
    this.notes,
    this.status = 'completed',
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_number': purchaseNumber,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'paid_amount': paidAmount,
      'outstanding_amount': outstandingAmount ?? (totalAmount - paidAmount),
      'payment_status': paymentStatus,
      'notes': notes,
      'status': status,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    // Include documentId for Firestore if present
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory Purchase.fromMap(Map<String, dynamic> map) {
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

    // Handle both int (SQLite) and String (Firestore) supplier IDs
    final supplierIdData = map['supplier_id'];
    dynamic supplierId;
    if (supplierIdData is int) {
      supplierId = supplierIdData;
    } else if (supplierIdData is String) {
      supplierId = supplierIdData;
    } else if (supplierIdData is num) {
      supplierId = supplierIdData.toInt();
    }

    return Purchase(
      id: idValue,
      documentId: docId,
      supplierId: supplierId,
      supplierName: map['supplier_name'] as String?,
      purchaseNumber: map['purchase_number'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      discountAmount: (map['discount_amount'] as num?)?.toDouble(),
      taxAmount: (map['tax_amount'] as num?)?.toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      outstandingAmount: (map['outstanding_amount'] as num?)?.toDouble() ?? ((map['total_amount'] as num).toDouble() - ((map['paid_amount'] as num?)?.toDouble() ?? 0.0)),
      paymentStatus: map['payment_status'] as String? ?? 'unpaid',
      notes: map['notes'] as String?,
      status: map['status'] as String? ?? 'completed',
      createdBy: (map['created_by'] as num?)?.toInt(),
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Purchase copyWith({
    int? id,
    String? documentId,
    dynamic supplierId,
    String? supplierName,
    String? purchaseNumber,
    double? totalAmount,
    double? discountAmount,
    double? taxAmount,
    double? paidAmount,
    double? outstandingAmount,
    String? paymentStatus,
    String? notes,
    String? status,
    int? createdBy,
    int? createdAt,
    int? updatedAt,
  }) {
    return Purchase(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      purchaseNumber: purchaseNumber ?? this.purchaseNumber,
      totalAmount: totalAmount ?? this.totalAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      outstandingAmount: outstandingAmount ?? this.outstandingAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
