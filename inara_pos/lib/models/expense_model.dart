/// Expense Model
/// Represents in-house expenses (rent, salary, utilities, etc.)
class Expense {
  final int? id;
  final String? documentId; // Firestore document ID (string)
  final String expenseNumber;
  final String title;
  final String? category;
  final double amount;
  final String? paymentMethod; // cash/card/bank_transfer/other
  final String? notes;
  final dynamic createdBy; // int for SQLite, String for Firestore
  final int createdAt;
  final int updatedAt;

  Expense({
    this.id,
    this.documentId,
    required this.expenseNumber,
    required this.title,
    this.category,
    required this.amount,
    this.paymentMethod,
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'expense_number': expenseNumber,
      'title': title,
      'category': category,
      'amount': amount,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    if (documentId != null) {
      map['document_id'] = documentId;
    }
    return map;
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
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

    return Expense(
      id: idValue,
      documentId: docId,
      expenseNumber: (map['expense_number'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      category: map['category'] as String?,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: map['payment_method'] as String?,
      notes: map['notes'] as String?,
      createdBy: map['created_by'],
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
