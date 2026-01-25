import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../providers/unified_database_provider.dart';
import '../../services/order_service.dart';
import '../../utils/number_formatter.dart';
import '../dashboard/dashboard_screen.dart';

class POSPaymentDialog extends StatefulWidget {
  final Order order;
  final OrderService orderService;

  const POSPaymentDialog({
    super.key,
    required this.order,
    required this.orderService,
  });

  @override
  State<POSPaymentDialog> createState() => _POSPaymentDialogState();
}

class _POSPaymentDialogState extends State<POSPaymentDialog> {
  String _selectedPaymentMethod = 'cash';
  final TextEditingController _amountController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.order.totalAmount.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),

            // Total amount
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text('Total Amount'),
                  const SizedBox(height: 8),
                  Text(
                    NumberFormatter.formatCurrency(widget.order.totalAmount),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment method
            Text(
              'Payment Method',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'card', label: Text('Card')),
                ButtonSegment(value: 'digital', label: Text('QR Payment')),
              ],
              selected: {_selectedPaymentMethod},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedPaymentMethod = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 24),

            // Amount (if partial payment)
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: 'Rs. ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            Navigator.of(context).pop();
                          },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _processPayment,
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirm Payment'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPayment() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (amount > widget.order.totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount cannot exceed total')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final createdBy = authProvider.currentUserId != null
          ? (kIsWeb
              ? authProvider.currentUserId!
              : int.tryParse(authProvider.currentUserId!))
          : null;

      final orderId = kIsWeb ? widget.order.documentId : widget.order.id;
      if (orderId == null) {
        throw Exception('Order ID not found');
      }

      await widget.orderService.completePayment(
        dbProvider: dbProvider,
        context: context,
        orderId: orderId,
        paymentMethod: _selectedPaymentMethod,
        amount: amount,
        createdBy: createdBy,
      );

      // NEW: Refresh dashboard to update sales and credit immediately
      DashboardScreen.refreshDashboard();

      if (mounted) {
        Navigator.of(context).pop({
          'success': true,
          'order_id': orderId,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}
