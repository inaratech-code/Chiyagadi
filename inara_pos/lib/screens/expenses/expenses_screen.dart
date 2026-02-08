import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/expense_service.dart';
import '../../models/expense_model.dart';
import '../../utils/theme.dart';
import '../../utils/performance.dart';

class ExpensesScreen extends StatefulWidget {
  final bool hideAppBar;
  const ExpensesScreen({super.key, this.hideAppBar = false});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final ExpenseService _expenseService = ExpenseService();
  bool _isLoading = false;
  List<Expense> _expenses = [];
  int _expensesLimit = 50;
  bool _canLoadMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExpenses());
  }

  Future<void> _loadExpenses() async {
    if (!mounted) return;
    try {
      final expenses = await _expenseService.getExpenses(
        context: context,
        limit: _expensesLimit,
      );
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _canLoadMore = expenses.length >= _expensesLimit;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading expenses: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddExpenseDialog() async {
    final titleController = TextEditingController();
    final categoryController = TextEditingController();
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String paymentMethod = 'cash';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g., Rent, Salary, Electricity',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    hintText: 'e.g., Utilities',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount (NPR) *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(
                        value: 'bank_transfer', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => paymentMethod = v ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: titleController.text.trim().isEmpty ||
                      amountController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.logoPrimary),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final title = titleController.text.trim();
    final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
    if (title.isEmpty || amount <= 0) return;

    try {
      await _expenseService.createExpense(
        context: context,
        title: title,
        amount: amount,
        category: categoryController.text.trim(),
        paymentMethod: paymentMethod,
        notes: notesController.text.trim(),
      );
      await _loadExpenses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Expense added'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<double>(0.0, (s, e) => s + e.amount);
    final currency = NumberFormat.currency(symbol: 'NPR ');

    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('In-house Expenses'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadExpenses,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showAddExpenseDialog,
                  tooltip: 'Add Expense',
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  child: Card(
                    color: AppTheme.logoLight.withOpacity(0.25),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            currency.format(total),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _expenses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payments,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No expenses found',
                                  style: TextStyle(color: Colors.grey[600])),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _showAddExpenseDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Expense'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.logoPrimary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          physics: platformScrollPhysics,
                          cacheExtent: 400,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _expenses.length + (_canLoadMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_canLoadMore && index == _expenses.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.only(top: 8, bottom: 24),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _expensesLimit += 50;
                                    });
                                    _loadExpenses();
                                  },
                                  child: const Text('Load more'),
                                ),
                              );
                            }
                            final e = _expenses[index];
                            final date = DateTime.fromMillisecondsSinceEpoch(
                                e.createdAt);
                            return RepaintBoundary(
                              child: Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.logoPrimary,
                                  child: const Icon(Icons.payments,
                                      color: Colors.white),
                                ),
                                title: Text(e.title),
                                subtitle: Text(
                                  [
                                    if ((e.category ?? '').trim().isNotEmpty)
                                      e.category!.trim(),
                                    DateFormat('MMM dd, yyyy').format(date),
                                    if ((e.paymentMethod ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      (e.paymentMethod ?? '')
                                          .replaceAll('_', ' '),
                                  ].join(' • '),
                                ),
                                trailing: Text(
                                  currency.format(e.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87),
                                ),
                              ),
                            ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expenses_fab',
        onPressed: _showAddExpenseDialog,
        backgroundColor: AppTheme.logoPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }
}
