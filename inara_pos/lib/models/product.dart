class Product {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final dynamic categoryId; // Can be int (SQLite) or String (Firestore)
  final String name;
  final String? description;
  final double price;
  final double cost;
  final String? imageUrl;
  final bool isVeg;
  final bool isActive;
  final bool isPurchasable; // Can be purchased from suppliers (raw materials, ingredients)
  final bool isSellable; // Can be sold to customers (menu items)
  final int createdAt;
  final int updatedAt;

  Product({
    this.id,
    this.documentId,
    required this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.cost = 0,
    this.imageUrl,
    this.isVeg = true,
    this.isActive = true,
    this.isPurchasable = false, // Default: not purchasable (menu items)
    this.isSellable = true, // Default: sellable (menu items)
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'price': price,
      'cost': cost,
      'image_url': imageUrl,
      'is_veg': isVeg ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'is_purchasable': isPurchasable ? 1 : 0,
      'is_sellable': isSellable ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    // Include documentId for Firestore if present
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory Product.fromMap(Map<String, dynamic> map) {
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
    
    // Handle both int (SQLite) and String (Firestore) category IDs
    final categoryIdData = map['category_id'];
    dynamic categoryId;
    if (categoryIdData is int) {
      categoryId = categoryIdData;
    } else if (categoryIdData is String) {
      categoryId = categoryIdData;
    } else if (categoryIdData is num) {
      categoryId = categoryIdData.toInt();
    } else {
      categoryId = 0; // Fallback
    }
    
    return Product(
      id: idValue,
      documentId: docId,
      categoryId: categoryId,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      imageUrl: map['image_url'] as String?,
      isVeg: (map['is_veg'] as int? ?? 1) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      isPurchasable: (map['is_purchasable'] as int? ?? 0) == 1,
      isSellable: (map['is_sellable'] as int? ?? 1) == 1,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Product copyWith({
    int? id,
    String? documentId,
    dynamic categoryId,
    String? name,
    String? description,
    double? price,
    double? cost,
    String? imageUrl,
    bool? isVeg,
    bool? isActive,
    bool? isPurchasable,
    bool? isSellable,
    int? createdAt,
    int? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      imageUrl: imageUrl ?? this.imageUrl,
      isVeg: isVeg ?? this.isVeg,
      isActive: isActive ?? this.isActive,
      isPurchasable: isPurchasable ?? this.isPurchasable,
      isSellable: isSellable ?? this.isSellable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
