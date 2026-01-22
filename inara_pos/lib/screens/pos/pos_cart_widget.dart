import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../services/order_service.dart';
import '../../utils/number_formatter.dart';
import '../../utils/theme.dart';

class POSCartWidget extends StatefulWidget {
  final Order? order;
  final String orderType;
  final int? selectedTableId;
  final Function(Order?)? onOrderUpdated;
  final Function(int?)? onTableSelected;
  final VoidCallback? onPayPressed;

  const POSCartWidget({
    super.key,
    this.order,
    required this.orderType,
    this.selectedTableId,
    this.onOrderUpdated,
    this.onTableSelected,
    this.onPayPressed,
  });

  @override
  State<POSCartWidget> createState() => _POSCartWidgetState();
}

class _POSCartWidgetState extends State<POSCartWidget> {
  final OrderService _orderService = OrderService();
  List<OrderItem> _items = [];
  bool _isLoading = false;

  dynamic _currentOrderId() {
    if (widget.order == null) return null;
    return kIsWeb ? widget.order!.documentId : widget.order!.id;
  }

  @override
  void initState() {
    super.initState();
    _loadOrderItems();
  }

  @override
  void didUpdateWidget(POSCartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if order identity changes OR order gets updated (items/totals changed)
    final oldOrderId =
        kIsWeb ? oldWidget.order?.documentId : oldWidget.order?.id;
    final newOrderId = kIsWeb ? widget.order?.documentId : widget.order?.id;
    if (oldOrderId != newOrderId ||
        oldWidget.order?.updatedAt != widget.order?.updatedAt) {
      _loadOrderItems();
    }
  }

  Future<void> _loadOrderItems() async {
    final orderId = _currentOrderId();
    if (orderId == null) {
      setState(() {
        _items = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final items =
          await _orderService.getOrderItemsAsObjects(dbProvider, orderId);
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.order == null) {
      return Container(
        color: const Color(0xFF2D2D2D),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                'Cart is empty',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select products to add',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF2D2D2D),
      child: Column(
        children: [
          // Order header - Improved design
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(
                bottom: BorderSide(color: Colors.grey[800]!, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.receipt_long,
                        size: 18,
                        color: Color(0xFFFFC107),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.order!.orderNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.orderType == 'dine_in'
                                  ? Colors.blue.withOpacity(0.2)
                                  : Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.orderType == 'dine_in'
                                  ? 'Dine-In'
                                  : 'Takeaway',
                              style: TextStyle(
                                color: widget.orderType == 'dine_in'
                                    ? AppTheme.logoPrimary
                                    : AppTheme.warningColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Text(
                          'Cart is empty',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildCartItem(item);
                        },
                      ),
          ),

          // Totals - Improved design
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(
                top: BorderSide(color: Colors.grey[800]!, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bill format: Subtotal, Discount (%), Total
                _buildTotalRow('Subtotal', widget.order!.subtotal),
                _buildTotalRow(
                  'Discount (${widget.order!.discountPercent.toStringAsFixed(1)}%)',
                  -widget.order!.discountAmount,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 1,
                  color: Colors.grey[800],
                ),
                const SizedBox(height: 8),
                _buildTotalRow(
                  'Total',
                  widget.order!.totalAmount,
                  isTotal: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: widget.order!.totalAmount > 0
                        ? widget.onPayPressed
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'PAY NOW',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Item ${item.productId}', // In real app, show product name
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    NumberFormatter.formatCurrency(item.totalPrice),
                    style: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${item.quantity} × ${NumberFormatter.formatCurrency(item.unitPrice)}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 18),
                        color: Colors.white,
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () {
                          if (item.id != null) {
                            _updateQuantity(item.id, item.quantity - 1);
                          }
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        color: Colors.white,
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () {
                          if (item.id != null) {
                            _updateQuantity(item.id, item.quantity + 1);
                          }
                        },
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: AppTheme.errorColor,
                          padding: const EdgeInsets.all(4),
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            if (item.id != null) {
                              _removeItem(item.id);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: isTotal ? 16 : 13,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            NumberFormatter.formatCurrency(amount),
            style: TextStyle(
              color: Colors.white,
              fontSize: isTotal ? 20 : 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateQuantity(dynamic itemId, int newQuantity) async {
    if (newQuantity <= 0) {
      await _removeItem(itemId);
      return;
    }

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      final createdBy = auth.currentUserId != null
          ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
          : null;
      await _orderService.updateItemQuantity(
        dbProvider: dbProvider,
        context: context,
        orderItemId: itemId,
        quantity: newQuantity,
        createdBy: createdBy,
      );
      await _loadOrderItems();
      // Reload order to update totals
      final orderId = _currentOrderId();
      if (orderId != null) {
        final updatedOrder =
            await _orderService.getOrderById(dbProvider, orderId);
        widget.onOrderUpdated?.call(updatedOrder);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _removeItem(dynamic itemId) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      final createdBy = auth.currentUserId != null
          ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
          : null;
      await _orderService.removeItemFromOrder(
        dbProvider: dbProvider,
        context: context,
        orderItemId: itemId,
        createdBy: createdBy,
      );
      await _loadOrderItems();
      // Reload order to update totals
      final orderId = _currentOrderId();
      if (orderId != null) {
        final updatedOrder =
            await _orderService.getOrderById(dbProvider, orderId);
        widget.onOrderUpdated?.call(updatedOrder);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
