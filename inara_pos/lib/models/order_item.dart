import 'product.dart';

class OrderItem {
  /// Can be int (SQLite) or String (Firestore document id)
  final dynamic id;

  /// Can be int (SQLite) or String (Firestore)
  final dynamic orderId;

  /// Can be int (SQLite) or String (Firestore)
  final dynamic productId;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;
  final int createdAt;

  // Join data (loaded separately)
  Product? product;

  OrderItem({
    this.id,
    required this.orderId,
    required this.productId,
    this.quantity = 1,
    required this.unitPrice,
    required this.totalPrice,
    this.notes,
    required this.createdAt,
    this.product,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    final quantityData = map['quantity'];
    final createdAtData = map['created_at'];
    return OrderItem(
      id: map['id'],
      orderId: map['order_id'],
      productId: map['product_id'],
      quantity: quantityData is num
          ? quantityData.toInt()
          : (quantityData as int? ?? 1),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      notes: map['notes'] as String?,
      createdAt: createdAtData is num
          ? createdAtData.toInt()
          : (createdAtData as int? ?? 0),
    );
  }

  OrderItem copyWith({
    dynamic id,
    dynamic orderId,
    dynamic productId,
    int? quantity,
    double? unitPrice,
    double? totalPrice,
    String? notes,
    int? createdAt,
    Product? product,
  }) {
    return OrderItem(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      product: product ?? this.product,
    );
  }
}
