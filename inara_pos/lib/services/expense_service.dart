import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/unified_database_provider.dart';
import '../providers/auth_provider.dart';
import '../models/expense_model.dart';

/// Expense Service
/// Handles in-house expenses CRUD.
class ExpenseService {
  Future<String> generateExpenseNumber({
    required BuildContext context,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final now = DateTime.now();
      final year = now.year % 100;
      final dateStr =
          '${year.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

      final startOfDay =
          DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59)
          .millisecondsSinceEpoch;

      final today = await dbProvider.query(
        'expenses',
        where: 'created_at >= ? AND created_at <= ? AND expense_number LIKE ?',
        whereArgs: [startOfDay, endOfDay, 'EXP $dateStr/%'],
      );

      int maxSequence = 0;
      final pattern = RegExp(r'EXP \d{6}/(\d+)');
      for (final row in today) {
        final n = row['expense_number'] as String?;
        if (n == null) continue;
        final match = pattern.firstMatch(n);
        if (match != null) {
          final seq = int.tryParse(match.group(1) ?? '0') ?? 0;
          if (seq > maxSequence) maxSequence = seq;
        }
      }

      final next = (maxSequence + 1).toString().padLeft(3, '0');
      return 'EXP $dateStr/$next';
    } catch (e) {
      debugPrint('Error generating expense number: $e');
      final now = DateTime.now();
      final year = now.year % 100;
      final dateStr =
          '${year.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      return 'EXP $dateStr/001';
    }
  }

  Future<dynamic> createExpense({
    required BuildContext context,
    required String title,
    required double amount,
    String? category,
    String? paymentMethod,
    String? notes,
  }) async {
    final dbProvider =
        Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await dbProvider.init();

    final now = DateTime.now().millisecondsSinceEpoch;
    final createdBy = authProvider.currentUserId != null
        ? (kIsWeb
            ? authProvider.currentUserId!
            : int.tryParse(authProvider.currentUserId!))
        : null;

    final expenseNumber = await generateExpenseNumber(context: context);

    return await dbProvider.insert('expenses', {
      'expense_number': expenseNumber,
      'title': title.trim(),
      'category': category?.trim().isEmpty == true ? null : category?.trim(),
      'amount': amount,
      'payment_method': paymentMethod,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
      'synced': 0,
    });
  }

  Future<List<Expense>> getExpenses({
    required BuildContext context,
    int? startMillis,
    int? endMillis,
  }) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      String? where;
      List<dynamic>? whereArgs;
      if (startMillis != null && endMillis != null) {
        where = 'created_at >= ? AND created_at <= ?';
        whereArgs = [startMillis, endMillis];
      }

      final rows = await dbProvider.query(
        'expenses',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'created_at DESC',
      );

      return rows.map((m) => Expense.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      return [];
    }
  }
}
