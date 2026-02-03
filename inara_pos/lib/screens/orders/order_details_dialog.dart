import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../services/order_service.dart';
import '../../utils/number_formatter.dart';
import 'order_payment_dialog.dart';

/// Dialog showing full order details: items, total, discount, customer name.
/// Actions: Pay, Edit order (full page), Close.
class OrderDetailsDialog extends StatefulWidget {
  final dynamic orderId;
  final String orderNumber;
  final OrderService orderService;
  /// Called when user taps Edit order; dialog is already popped. Use to push OrderDetailScreen and refresh list.
  final VoidCallback? onEditOrder;

  const OrderDetailsDialog({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.orderService,
    this.onEditOrder,
  });

  @override
  State<OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<OrderDetailsDialog> {
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _orderItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final orders = await dbProvider.query(
        'orders',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [widget.orderId],
      );
      if (orders.isNotEmpty) _order = orders.first;

      _orderItems = await dbProvider.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [widget.orderId],
      );
    } catch (e) {
      debugPrint('OrderDetailsDialog load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _subtotal {
    return _orderItems.fold(
        0.0, (sum, item) => sum + ((item['total_price'] as num?)?.toDouble() ?? 0.0));
  }

  double get _discountAmount =>
      (_order?['discount_amount'] as num?)?.toDouble() ?? 0.0;

  double get _total =>
      (_order?['total_amount'] as num?)?.toDouble() ?? (_subtotal - _discountAmount);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 420,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order ${widget.orderNumber}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Order info
                      _order == null
                          ? const SizedBox.shrink()
                          : _buildOrderInfo(),
                      const SizedBox(height: 16),
                      // Items
                      Text(
                        'Items',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      _orderItems.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No items in this order',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _orderItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final item = _orderItems[index];
                                final name = item['product_name'] as String? ?? 'Item';
                                final qty = (item['quantity'] as num?)?.toInt() ?? 0;
                                final total = (item['total_price'] as num?)?.toDouble() ?? 0.0;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$name × $qty',
                                        style: const TextStyle(fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      NumberFormatter.formatCurrency(total),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                      const SizedBox(height: 16),
                      // Totals
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            _buildTotalRow('Subtotal', _subtotal),
                            if (_discountAmount > 0)
                              _buildTotalRow('Discount', -_discountAmount),
                            const Divider(height: 16),
                            _buildTotalRow('Total', _total, isTotal: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Actions
                      Row(
                        children: [
                          if (_order?['payment_status'] != 'paid') ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _openPayment(),
                                icon: const Icon(Icons.payment, size: 20),
                                label: const Text('Pay'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _openEditOrder(),
                              icon: const Icon(Icons.edit, size: 20),
                              label: const Text('Edit order'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderInfo() {
    final orderType = _order!['order_type'] == 'dine_in' ? 'Dine-In' : 'Takeaway';
    final paymentStatus = _order!['payment_status'] as String? ?? 'unpaid';
    final customerName = _order!['customer_name'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type: $orderType', style: const TextStyle(fontSize: 14)),
          Text('Payment: ${paymentStatus == 'paid' ? 'Paid' : 'Unpaid'}',
              style: const TextStyle(fontSize: 14)),
          if (customerName != null && customerName.toString().trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Customer: ${customerName.toString().trim()}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            NumberFormatter.formatCurrency(amount),
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPayment() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => OrderPaymentDialog(
        orderId: widget.orderId,
        orderNumber: widget.orderNumber,
        totalAmount: _total,
        orderService: widget.orderService,
      ),
    );
    if (!mounted) return;
    if (result != null && result['success'] == true) {
      await _loadData();
    }
  }

  void _openEditOrder() {
    Navigator.pop(context);
    widget.onEditOrder?.call();
  }
}
