/// Purchase Item Model
/// Represents a single product item in a purchase order
class PurchaseItem {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final dynamic purchaseId; // Can be int (SQLite) or String (Firestore)
  final dynamic productId; // Can be int (SQLite) or String (Firestore)
  final String? productName; // Denormalized for display
  final String unit; // pcs/kg/ltr etc
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;

  PurchaseItem({
    this.id,
    this.documentId,
    required this.purchaseId,
    required this.productId,
    this.productName,
    this.unit = 'pcs',
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'purchase_id': purchaseId,
      'product_id': productId,
      'product_name': productName,
      'unit': unit,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
    };
    // Include documentId for Firestore if present
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory PurchaseItem.fromMap(Map<String, dynamic> map) {
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

    // Handle both int (SQLite) and String (Firestore) IDs
    final purchaseIdData = map['purchase_id'];
    dynamic purchaseId;
    if (purchaseIdData is int) {
      purchaseId = purchaseIdData;
    } else if (purchaseIdData is String) {
      purchaseId = purchaseIdData;
    } else if (purchaseIdData is num) {
      purchaseId = purchaseIdData.toInt();
    }

    final productIdData = map['product_id'];
    dynamic productId;
    if (productIdData is int) {
      productId = productIdData;
    } else if (productIdData is String) {
      productId = productIdData;
    } else if (productIdData is num) {
      productId = productIdData.toInt();
    }

    return PurchaseItem(
      id: idValue,
      documentId: docId,
      purchaseId: purchaseId,
      productId: productId,
      productName: map['product_name'] as String?,
      unit: map['unit'] as String? ?? 'pcs',
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      notes: map['notes'] as String?,
    );
  }

  PurchaseItem copyWith({
    int? id,
    String? documentId,
    dynamic purchaseId,
    dynamic productId,
    String? productName,
    String? unit,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    String? notes,
  }) {
    return PurchaseItem(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      purchaseId: purchaseId ?? this.purchaseId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      notes: notes ?? this.notes,
    );
  }
}
