/// Inventory Ledger Model
/// Represents a single entry in the inventory ledger
/// Stock is NEVER stored directly - it's calculated from ledger entries
/// Current Stock = Sum(quantityIn) - Sum(quantityOut)
class InventoryLedger {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final dynamic productId; // Can be int (SQLite) or String (Firestore)
  final String? productName; // Denormalized for display
  final double quantityIn; // Stock increase (from purchases, adjustments, etc.)
  final double quantityOut; // Stock decrease (from sales, adjustments, etc.)
  final double unitPrice; // Price per unit at time of transaction
  final String transactionType; // 'purchase', 'sale', 'adjustment', 'return', 'correction'
  final String? referenceType; // 'purchase', 'order', 'adjustment', etc.
  final dynamic referenceId; // ID of the reference document (purchase_id, order_id, etc.)
  final String? notes;
  final int? createdBy;
  final int createdAt;

  InventoryLedger({
    this.id,
    this.documentId,
    required this.productId,
    this.productName,
    this.quantityIn = 0.0,
    this.quantityOut = 0.0,
    this.unitPrice = 0.0,
    required this.transactionType,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'quantity_in': quantityIn,
      'quantity_out': quantityOut,
      'unit_price': unitPrice,
      'transaction_type': transactionType,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt,
    };
    // Include documentId for Firestore if present
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory InventoryLedger.fromMap(Map<String, dynamic> map) {
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

    // Handle both int (SQLite) and String (Firestore) product IDs
    final productIdData = map['product_id'];
    dynamic productId;
    if (productIdData is int) {
      productId = productIdData;
    } else if (productIdData is String) {
      productId = productIdData;
    } else if (productIdData is num) {
      productId = productIdData.toInt();
    }

    // Handle reference_id (can be int or String)
    final referenceIdData = map['reference_id'];
    dynamic referenceId;
    if (referenceIdData != null) {
      if (referenceIdData is int) {
        referenceId = referenceIdData;
      } else if (referenceIdData is String) {
        referenceId = referenceIdData;
      } else if (referenceIdData is num) {
        referenceId = referenceIdData.toInt();
      }
    }

    return InventoryLedger(
      id: idValue,
      documentId: docId,
      productId: productId,
      productName: map['product_name'] as String?,
      quantityIn: (map['quantity_in'] as num?)?.toDouble() ?? 0.0,
      quantityOut: (map['quantity_out'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
      transactionType: map['transaction_type'] as String,
      referenceType: map['reference_type'] as String?,
      referenceId: referenceId,
      notes: map['notes'] as String?,
      createdBy: (map['created_by'] as num?)?.toInt(),
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  InventoryLedger copyWith({
    int? id,
    String? documentId,
    dynamic productId,
    String? productName,
    double? quantityIn,
    double? quantityOut,
    double? unitPrice,
    String? transactionType,
    String? referenceType,
    dynamic referenceId,
    String? notes,
    int? createdBy,
    int? createdAt,
  }) {
    return InventoryLedger(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantityIn: quantityIn ?? this.quantityIn,
      quantityOut: quantityOut ?? this.quantityOut,
      unitPrice: unitPrice ?? this.unitPrice,
      transactionType: transactionType ?? this.transactionType,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
