import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:provider/provider.dart';
import '../providers/unified_database_provider.dart';
import '../providers/auth_provider.dart' show InaraAuthProvider;
import '../models/product.dart';
import '../services/order_service.dart';
import '../screens/orders/orders_screen.dart';

/// UPDATED: Order overlay widget matching 2nd image design (Create Order modal)
/// Shows searchable menu items with quantity controls, matching the Create Order dialog
class OrderOverlayWidget extends StatefulWidget {
  final dynamic orderId;
  final String orderNumber;

  /// Pending items from menu cart - when provided, order is NOT in DB until Create Order
  final List<Map<String, dynamic>>? pendingItems;
  final VoidCallback? onClose;
  final VoidCallback? onOrderUpdated;
  final VoidCallback?
      onOrderCreated; // Called when order created from pending items
  /// Callback to sync pending items back when overlay closes without creating
  final void Function(List<Map<String, dynamic>>)? onPendingItemsChanged;
  final int refreshKey;

  const OrderOverlayWidget({
    super.key,
    this.orderId,
    required this.orderNumber,
    this.pendingItems,
    this.onClose,
    this.onOrderUpdated,
    this.onOrderCreated,
    this.onPendingItemsChanged,
    this.refreshKey = 0,
  });

  @override
  State<OrderOverlayWidget> createState() => _OrderOverlayWidgetState();
}

class _OrderOverlayWidgetState extends State<OrderOverlayWidget> {
  final OrderService _orderService = OrderService();
  List<Map<String, dynamic>> _orderItems = [];
  Map<String, dynamic>? _order;
  List<Product> _products = [];
  bool _isLoading = false;
  final TextEditingController _discountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didUpdateWidget(OrderOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.pendingItems != widget.pendingItems) {
      _loadData();
    }
  }

  bool get _isPendingMode =>
      widget.pendingItems != null && widget.orderId == null;

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  // Check if order should be deleted when cancelled (no items and pending status)
  Future<bool> _shouldDeleteOnCancel() async {
    if (widget.orderId == null) return false;
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final items =
          await _orderService.getOrderItems(dbProvider, widget.orderId!);
      final orders = await dbProvider.query(
        'orders',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [widget.orderId],
      );

      if (orders.isEmpty) return false;

      final order = orders.first;
      final status = order['status'] as String? ?? 'pending';
      final hasItems = items.isNotEmpty;

      // Delete if order has no items and is in pending/confirmed status (not paid)
      return !hasItems && (status == 'pending' || status == 'confirmed');
    } catch (e) {
      debugPrint('OrderOverlay: Error checking if should delete: $e');
      return false;
    }
  }

  // Handle close with order deletion if needed
  Future<void> _handleClose() async {
    if (_isPendingMode) {
      final items = _orderItems
          .where((i) => ((i['quantity'] as num?)?.toInt() ?? 0) > 0)
          .map((i) {
            final product = i['product'] as Product?;
            if (product != null) {
              return {
                'product': product,
                'quantity': (i['quantity'] as num?)?.toInt() ?? 1
              };
            }
            try {
              final p = _products.firstWhere((p) =>
                  (kIsWeb ? p.documentId : p.id)?.toString() ==
                  i['product_id']?.toString());
              return {
                'product': p,
                'quantity': (i['quantity'] as num?)?.toInt() ?? 1
              };
            } catch (_) {
              return null;
            }
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      widget.onPendingItemsChanged?.call(items);
      widget.onClose?.call();
      return;
    }
    final shouldDelete = await _shouldDeleteOnCancel();

    if (shouldDelete) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await _orderService.deleteOrder(
          dbProvider: dbProvider,
          context: context,
          orderId: widget.orderId,
        );
        debugPrint(
            'OrderOverlay: Deleted empty order ${widget.orderNumber} on cancel');
      } catch (e) {
        debugPrint('OrderOverlay: Error deleting order on cancel: $e');
        // Continue to close even if deletion fails
      }
    }

    widget.onClose?.call();
  }

  Future<void> _loadData() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      if (_isPendingMode && widget.pendingItems != null) {
        // Pending mode: convert pending cart items to _orderItems format
        _order = null;
        _discountController.text = '0';
        _orderItems = widget.pendingItems!.map((item) {
          final product = item['product'] as Product;
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final productId = kIsWeb ? product.documentId : product.id;
          return {
            'product_id': productId,
            'product_name': product.name,
            'unit_price': product.price,
            'quantity': qty,
            'total_price': product.price * qty,
            'product': product,
          };
        }).toList();
        debugPrint('OrderOverlay: Loaded ${_orderItems.length} pending items');
      } else {
        // Order mode: load from DB
        debugPrint('OrderOverlay: Loading data for orderId: ${widget.orderId}');

        final orders = await dbProvider.query(
          'orders',
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [widget.orderId],
        );
        if (orders.isNotEmpty) {
          _order = orders.first;
          _discountController.text =
              (_order!['discount_percent'] as num? ?? 0.0).toStringAsFixed(1);
        }

        final items =
            await _orderService.getOrderItems(dbProvider, widget.orderId!);
        _orderItems = items;
      }

      // Load all sellable products
      final productMaps = kIsWeb
          ? await dbProvider.query(
              'products',
              where: 'is_sellable = ?',
              whereArgs: [1],
            )
          : await dbProvider.query(
              'products',
              where:
                  'is_sellable = ? OR (is_sellable IS NULL OR is_sellable = 1)',
              whereArgs: [1],
            );
      _products = productMaps
          .map((m) => Product.fromMap(m))
          .where((p) => p.isSellable)
          .toList();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading order: $e')),
        );
      }
    }
  }

  Future<void> _updateItemQuantity(Product product, int newQuantity) async {
    try {
      final productId = kIsWeb ? product.documentId : product.id;

      if (_isPendingMode) {
        // Pending mode: update local _orderItems only
        if (newQuantity <= 0) {
          _orderItems.removeWhere((item) =>
              item['product_id']?.toString() == productId?.toString());
        } else {
          final idx = _orderItems.indexWhere((item) =>
              item['product_id']?.toString() == productId?.toString());
          if (idx >= 0) {
            _orderItems[idx]['quantity'] = newQuantity;
            _orderItems[idx]['total_price'] = product.price * newQuantity;
          } else {
            _orderItems.add({
              'product_id': productId,
              'product_name': product.name,
              'unit_price': product.price,
              'quantity': newQuantity,
              'total_price': product.price * newQuantity,
              'product': product,
            });
          }
        }
        setState(() {});
        widget.onOrderUpdated?.call();
        return;
      }

      // Order mode: update in DB
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);

      if (newQuantity <= 0) {
        final item = _orderItems.firstWhere(
          (item) => item['product_id']?.toString() == productId?.toString(),
          orElse: () => {},
        );
        if (item.isNotEmpty) {
          final itemId = item['id'] ?? item['documentId'];
          final auth = Provider.of<InaraAuthProvider>(context, listen: false);
          final createdBy = auth.currentUserId != null
              ? (kIsWeb
                  ? auth.currentUserId!
                  : int.tryParse(auth.currentUserId!))
              : null;
          await _orderService.removeItemFromOrder(
            dbProvider: dbProvider,
            context: context,
            orderItemId: itemId,
            createdBy: createdBy,
          );
        }
      } else {
        final item = _orderItems.firstWhere(
          (item) => item['product_id']?.toString() == productId?.toString(),
          orElse: () => {},
        );
        final auth = Provider.of<InaraAuthProvider>(context, listen: false);
        final createdBy = auth.currentUserId != null
            ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
            : null;

        if (item.isEmpty) {
          await _orderService.addItemToOrder(
            dbProvider: dbProvider,
            context: context,
            orderId: widget.orderId,
            product: product,
            quantity: newQuantity,
            createdBy: createdBy,
          );
        } else {
          final itemId = item['id'] ?? item['documentId'];
          await _orderService.updateItemQuantity(
            dbProvider: dbProvider,
            context: context,
            orderItemId: itemId,
            quantity: newQuantity,
            createdBy: createdBy,
          );
        }
      }

      await _loadData();
      widget.onOrderUpdated?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newQuantity > 0
                ? 'Updated ${product.name}'
                : 'Removed ${product.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating item quantity: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating item: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  double get _subtotal {
    double total = 0;
    for (final item in _orderItems) {
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0;
      final qty = (item['quantity'] as num?)?.toInt() ?? 0;
      total += price * qty;
    }
    return total;
  }

  double get _discountAmount {
    final percent = double.tryParse(_discountController.text) ?? 0.0;
    return _subtotal * (percent / 100.0);
  }

  double get _total {
    return _subtotal - _discountAmount;
  }

  Future<void> _updateVATAndDiscount() async {
    final discountPercent = double.tryParse(_discountController.text) ?? 0.0;

    if (discountPercent < 0 || discountPercent > 100) {
      return;
    }

    if (_isPendingMode) {
      setState(() {}); // Rebuild to show updated totals
      return;
    }

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await _orderService.updateVATAndDiscount(
        dbProvider: dbProvider,
        orderId: widget.orderId,
        vatPercent: 0.0,
        discountPercent: discountPercent,
      );
      await _loadData();
      widget.onOrderUpdated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating: $e')),
        );
      }
    }
  }

  // Create/finalize order - either from pending cart or update existing order
  Future<void> _createOrder() async {
    if (_orderItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add items to the order'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      final createdBy = auth.currentUserId != null
          ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
          : null;
      final discountPercent = double.tryParse(_discountController.text) ?? 0.0;
      final subtotal = _subtotal;
      final discountAmount = subtotal * (discountPercent / 100);
      final total = subtotal - discountAmount;

      if (_isPendingMode) {
        // Create order in DB for the first time (order does NOT exist yet)
        final orderId = await _orderService.createOrder(
          dbProvider: dbProvider,
          orderType: 'dine_in',
          createdBy: createdBy,
        );

        // Add all items to the new order (pending items have 'product' key)
        for (final item in _orderItems) {
          Product? product = item['product'] as Product?;
          if (product == null && _products.isNotEmpty) {
            try {
              product = _products.firstWhere((p) =>
                  (kIsWeb ? p.documentId : p.id)?.toString() ==
                  item['product_id']?.toString());
            } catch (_) {}
          }
          if (product != null) {
            final qty = (item['quantity'] as num?)?.toInt() ?? 1;
            await _orderService.addItemToOrder(
              dbProvider: dbProvider,
              context: context,
              orderId: orderId,
              product: product,
              quantity: qty,
              createdBy: createdBy,
            );
          }
        }

        // Update order totals and status
        await dbProvider.update(
          'orders',
          values: {
            'subtotal': subtotal,
            'discount_percent': discountPercent,
            'discount_amount': discountAmount,
            'tax_percent': 0.0,
            'tax_amount': 0.0,
            'total_amount': total,
            'status': 'confirmed',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [orderId],
        );

        debugPrint('OrderOverlay: Created new order from pending cart');
        widget.onOrderCreated?.call();
      } else {
        // Order mode: save updates and confirm
        await _saveOrderUpdates();
        await dbProvider.update(
          'orders',
          values: {
            'status': 'confirmed',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [widget.orderId],
        );
        widget.onClose?.call();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order created successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const OrdersScreen(),
          ),
        );
      }
    } catch (e) {
      debugPrint('OrderOverlay: Error creating order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating order: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // UPDATED: Save order updates (VAT, discount) before payment
  Future<void> _saveOrderUpdates() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final discountPercent = double.tryParse(_discountController.text) ?? 0.0;

      // Calculate totals
      final subtotal = _subtotal;
      final discountAmount = (subtotal * discountPercent / 100);
      final total = subtotal - discountAmount;

      // Update order with current totals
      await dbProvider.update(
        'orders',
        values: {
          'subtotal': subtotal,
          'discount_percent': discountPercent,
          'discount_amount': discountAmount,
          'tax_percent': 0.0,
          'tax_amount': 0.0,
          'total_amount': total,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [widget.orderId],
      );

      debugPrint('OrderOverlay: Saved order updates for ${widget.orderNumber}');
    } catch (e) {
      debugPrint('OrderOverlay: Error saving order updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.white,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      color: Colors.white,
      child: Material(
        color: Colors.white,
        child: Column(
          children: [
            // UPDATED: Header matching 2nd image - "Create Order" with X button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'Create Order',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _handleClose,
                  ),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // UPDATED: Order Type and Table dropdowns matching 2nd image
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: 'dine_in',
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'dine_in',
                                    child: Text('Dine-In'),
                                  ),
                                ],
                                onChanged: null, // Disabled - only Dine-In
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(4),
                                  color: Colors.grey[200],
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: 'no_table',
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'no_table',
                                        child: Text('No Table'),
                                      ),
                                    ],
                                    onChanged: null, // Disabled for now
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Only for Dine-In',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Discount input
                    TextField(
                      controller: _discountController,
                      decoration: InputDecoration(
                        labelText: 'Discount %',
                        border: const OutlineInputBorder(),
                        suffixText: '%',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _updateVATAndDiscount(),
                    ),

                    const SizedBox(height: 16),

                    // UPDATED: Show only items that are in the order (quantity > 0)
                    const Text(
                      'Order Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final itemsWithQuantity = _orderItems.where((item) {
                          final quantity =
                              (item['quantity'] as num?)?.toInt() ?? 0;
                          return quantity > 0;
                        }).toList();

                        debugPrint(
                            'OrderOverlay: Rendering - total items: ${_orderItems.length}, items with quantity > 0: ${itemsWithQuantity.length}');

                        if (itemsWithQuantity.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(32),
                            child: const Center(
                              child: Text(
                                'No items in order',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: itemsWithQuantity.map((item) {
                            Product product;
                            if (item['product'] != null) {
                              product = item['product'] as Product;
                            } else {
                              try {
                                product = _products.firstWhere((p) =>
                                    (kIsWeb ? p.documentId : p.id)
                                        ?.toString() ==
                                    item['product_id']?.toString());
                              } catch (_) {
                                product = Product(
                                  categoryId: 0,
                                  name: item['product_name'] as String? ??
                                      'Unknown',
                                  price: (item['unit_price'] as num?)
                                          ?.toDouble() ??
                                      0,
                                  createdAt: 0,
                                  updatedAt: 0,
                                );
                              }
                            }
                            final quantity =
                                (item['quantity'] as num?)?.toInt() ?? 0;
                            return _buildMenuItemRow(product, quantity);
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // UPDATED: Order summary matching 2nd image
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildSummaryRow('Subtotal', _subtotal),
                          _buildSummaryRow(
                            'Discount (${double.tryParse(_discountController.text)?.toStringAsFixed(1) ?? '0.0'}%)',
                            -_discountAmount,
                          ),
                          const Divider(),
                          _buildSummaryRow('Total', _total, isTotal: true),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // UPDATED: Cancel and Create Order buttons matching 2nd image
                    // Added bottom padding to prevent overlap with bottom navigation
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom +
                            16, // Account for bottom nav and safe area
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _handleClose,
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: Colors.grey[400]!),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  _orderItems.isEmpty ? null : _createOrder,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFFFFC107), // Yellow/orange
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text(
                                'Create Order',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildMenuItemRow(Product product, int quantity) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Item name and price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Price: NPR ${product.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          // Quantity controls matching 2nd image (- 0 +)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: quantity > 0
                    ? () => _updateItemQuantity(product, quantity - 1)
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  padding: const EdgeInsets.all(8),
                ),
              ),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text(
                  '$quantity',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _updateItemQuantity(product, quantity + 1),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
            'NPR ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
