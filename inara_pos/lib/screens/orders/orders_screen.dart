import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../services/order_service.dart';
import '../../services/inventory_ledger_service.dart';
import '../../models/product.dart';
import '../../widgets/responsive_wrapper.dart';
import '../../utils/theme.dart';
import '../../utils/app_messenger.dart';
import 'order_detail_screen.dart';
import 'order_payment_dialog.dart';
import 'package:intl/intl.dart';

class OrdersScreen extends StatefulWidget {
  final bool hideAppBar;
  const OrdersScreen({super.key, this.hideAppBar = false});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final OrderService _orderService = OrderService();
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String _filterStatus = 'all'; // 'all', 'pending', 'completed', 'cancelled'
  int _ordersLimit = 50;
  bool _canLoadMore = false;

  // NEW: Sensitive action confirmation (password)
  Future<bool> _confirmAdminPin() async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final pinController = TextEditingController();
    bool obscurePassword = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Password Required'),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.text,
            obscureText: obscurePassword,
            maxLength: 20,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: '4-20 characters',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setDialogState(() {
                    obscurePassword = !obscurePassword;
                  });
                },
                tooltip: obscurePassword ? 'Show password' : 'Hide password',
              ),
            ),
          ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final valid = await auth.verifyAdminPin(pinController.text.trim());
              if (!valid) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid Password'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
      ),
    );
    return ok == true;
  }

  Future<void> _deleteOrderWithConfirmation({
    required dynamic orderId,
    required String orderNumber,
  }) async {
    // NEW: Role-based access + password-protected deletion
    final okPin = await _confirmAdminPin();
    if (!okPin) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Order?'),
        content: Text(
            'Delete $orderNumber permanently? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await _orderService.deleteOrder(
        dbProvider: dbProvider,
        context: context,
        orderId: orderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order deleted'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrders());
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // UPDATED: Query by order_type only, filter status in-memory to avoid Firestore composite index
      final allOrders = await dbProvider.query(
        'orders',
        where: 'order_type = ?',
        whereArgs: ['dine_in'],
        orderBy: 'created_at DESC',
        limit: _ordersLimit * 2, // Get more to account for filtering
      );

      // Filter by status in-memory
      final orders = _filterStatus == 'all'
          ? allOrders
          : allOrders.where((o) => o['status'] == _filterStatus).toList();

      // Limit after filtering
      final limitedOrders = orders.take(_ordersLimit).toList();

      if (!mounted) return;
      _orders = limitedOrders;
      _canLoadMore = orders.length >= _ordersLimit;
    } catch (e) {
      debugPrint('Error loading orders: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    return _orders;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String _getPaymentStatusLabel(Map<String, dynamic> order) {
    final paymentStatus = order['payment_status'] as String? ?? 'unpaid';
    final creditAmount = (order['credit_amount'] as num? ?? 0).toDouble();
    final paymentMethod = order['payment_method'] as String?;

    // If there is credit due, always show "Credit" (not Paid).
    if (creditAmount > 0 || paymentMethod == 'credit') {
      return 'Credit';
    }

    if (paymentStatus == 'paid') {
      return 'Paid';
    } else if (paymentStatus == 'partial') {
      if (creditAmount > 0) {
        return 'Partial + Credit';
      }
      return 'Partial';
    } else if (creditAmount > 0) {
      return 'Credit';
    }
    return 'Unpaid';
  }

  Color _getPaymentStatusColor(Map<String, dynamic> order) {
    final paymentStatus = order['payment_status'] as String? ?? 'unpaid';
    final creditAmount = (order['credit_amount'] as num? ?? 0).toDouble();
    final paymentMethod = order['payment_method'] as String?;

    if (creditAmount > 0 || paymentMethod == 'credit') {
      return AppTheme.warningColor;
    }
    if (paymentStatus == 'paid') {
      return Colors.green;
    } else if (paymentStatus == 'partial' || creditAmount > 0) {
      return Colors.orange;
    }
    return Colors.red;
  }

  String _getPaymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Cash';
      case 'digital':
        return 'QR Payment';
      case 'credit':
        return 'Credit';
      default:
        return method;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              elevation: 0,
              title: const Text(
                'Orders',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadOrders,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateOrderDialog(),
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pending'),
                  const SizedBox(width: 8),
                  _buildFilterChip('completed', 'Completed'),
                  const SizedBox(width: 8),
                  _buildFilterChip('cancelled', 'Cancelled'),
                ],
              ),
            ),
          ),

          // Orders list
          Expanded(
            child: kIsWeb
                ? ResponsiveWrapper(
                    padding: EdgeInsets.zero,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredOrders.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt_long,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No orders found',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadOrders,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredOrders.length +
                                      (_canLoadMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (_canLoadMore &&
                                        index == _filteredOrders.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                            top: 8, bottom: 24),
                                        child: OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              _ordersLimit += 50;
                                            });
                                            _loadOrders();
                                          },
                                          child: const Text('Load more'),
                                        ),
                                      );
                                    }
                                    final order = _filteredOrders[index];
                                    return _buildOrderCard(order);
                                  },
                                ),
                              ),
                  )
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredOrders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No orders found',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadOrders,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredOrders.length +
                                  (_canLoadMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_canLoadMore &&
                                    index == _filteredOrders.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 24),
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _ordersLimit += 50;
                                        });
                                        _loadOrders();
                                      },
                                      child: const Text('Load more'),
                                    ),
                                  );
                                }
                                final order = _filteredOrders[index];
                                return _buildOrderCard(order);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String status, String label) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = status;
          _ordersLimit = 50;
          _canLoadMore = false;
        });
        _loadOrders();
      },
      selectedColor: Theme.of(context).primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'pending';
    final statusColor = _getStatusColor(status);
    final orderType = order['order_type'] as String? ?? 'dine_in';

    // FIXED: Handle both SQLite (id) and Firestore (documentId) order IDs
    final orderId = kIsWeb ? (order['documentId'] ?? order['id']) : order['id'];
    final totalAmount = (order['total_amount'] as num? ?? 0).toDouble();
    final paymentStatus = order['payment_status'] as String? ?? 'unpaid';
    final creditAmount = (order['credit_amount'] as num? ?? 0).toDouble();
    final paymentMethod = order['payment_method'] as String?;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        // UX change: Tap = Payment dialog. Long-press = Details screen.
        onTap: () async {
          if (paymentStatus == 'paid') {
            AppMessenger.showSnackBar('Order already paid');
            return;
          }

          final result = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => OrderPaymentDialog(
              orderId: orderId,
              orderNumber: order['order_number'] as String? ?? 'Order',
              totalAmount: totalAmount,
              orderService: _orderService,
            ),
          );

          if (result != null && result['success'] == true) {
            await _loadOrders();
          }
        },
        onLongPress: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailScreen(
                orderId: orderId, // FIXED: Use dynamic orderId
                orderNumber: order['order_number'] as String,
              ),
            ),
          ).then((_) => _loadOrders());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['order_number'] as String? ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              orderType == 'dine_in'
                                  ? Icons.table_restaurant
                                  : Icons.shopping_bag,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              orderType == 'dine_in' ? 'Dine-In' : 'Takeaway',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            // REMOVED: Date display as requested
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1.5),
                    ),
                    child: Text(
                      _getStatusLabel(status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // UPDATED: Edit button - opens order detail screen for editing
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'Edit order',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrderDetailScreen(
                            orderId: orderId,
                            orderNumber: order['order_number'] as String? ?? 'Order',
                          ),
                        ),
                      ).then((_) => _loadOrders());
                    },
                  ),
                  const SizedBox(width: 8),
                  // NEW: Delete button (password-protected)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete order',
                    onPressed: () => _deleteOrderWithConfirmation(
                      orderId: orderId,
                      orderNumber: order['order_number'] as String? ?? 'Order',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Status',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _getPaymentStatusLabel(order),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _getPaymentStatusColor(order),
                            ),
                          ),
                          // Avoid showing "Paid • Credit" (Credit label already displayed above).
                          if (paymentMethod != null &&
                              paymentMethod != 'credit')
                            Text(
                              ' • ${_getPaymentMethodLabel(order['payment_method'] as String)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        NumberFormat.currency(symbol: 'NPR ')
                            .format(order['total_amount'] ?? 0),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if ((order['credit_amount'] as num? ?? 0) > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Credit: ${NumberFormat.currency(symbol: 'NPR ').format(order['credit_amount'])}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (order['payment_status'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        (paymentStatus == 'paid' && creditAmount <= 0)
                            ? Icons.check_circle
                            : Icons.pending,
                        size: 16,
                        color: (paymentStatus == 'paid' && creditAmount <= 0)
                            ? Colors.green
                            : AppTheme.warningColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        (paymentStatus == 'paid' && creditAmount <= 0)
                            ? 'Paid'
                            : (creditAmount > 0 ? 'Credit' : 'Unpaid'),
                        style: TextStyle(
                          fontSize: 12,
                          color: (paymentStatus == 'paid' && creditAmount <= 0)
                              ? Colors.green
                              : AppTheme.warningColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // PERF: Don't show item preview here (it forces N+1 queries on web).
              // Item details are shown in Order Detail screen.
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateOrderDialog() async {
    final dbProvider =
        Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    await dbProvider.init();
    final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);

    // Dialog state
    String orderType = 'takeaway';
    dynamic selectedTableId;
    double discountPercent = 0.0;
    final searchController = TextEditingController();
    final Map<dynamic, int> qty = {};

    // Load tables
    final tables = await dbProvider
        .query('tables', where: 'status = ?', whereArgs: ['available']);

    // Load sellable products (no category selection needed here)
    List<Map<String, dynamic>> productMaps;
    if (kIsWeb) {
      final allProducts = await dbProvider.query(
        'products',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );
      productMaps = allProducts.where((p) {
        final isSellable = p['is_sellable'];
        return isSellable == null || isSellable == 1;
      }).toList();
    } else {
      productMaps = await dbProvider.query(
        'products',
        where: 'is_active = ? AND (is_sellable = ? OR is_sellable IS NULL)',
        whereArgs: [1, 1],
        orderBy: 'name ASC',
      );
    }
    final products = productMaps.map((m) => Product.fromMap(m)).toList();

    // PERF: Don't prefetch stock for all products (slow on web for large catalogs).
    // We validate stock for ONLY the selected items right before creating the order.
    final ledgerService = InventoryLedgerService();

    double calcSubtotal() {
      double sum = 0.0;
      for (final entry in qty.entries) {
        if (entry.value <= 0) continue;
        final product = products.firstWhere((p) {
          final pid = kIsWeb ? p.documentId : p.id;
          return pid == entry.key;
        });
        sum += product.price * entry.value;
      }
      return sum;
    }

    double calcDiscountAmount(double subtotal) =>
        subtotal * (discountPercent / 100.0);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = searchController.text.trim().toLowerCase();
          final filtered = products.where((p) {
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q);
          }).toList();

          final subtotal = calcSubtotal();
          final discountAmount = calcDiscountAmount(subtotal);
          final total = subtotal - discountAmount;
          final hasItems = qty.values.any((v) => v > 0);

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 720,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Create Order',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Order Type + Optional Table
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: orderType,
                            decoration: const InputDecoration(
                              labelText: 'Order Type',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'dine_in', child: Text('Dine-In')),
                              DropdownMenuItem(
                                  value: 'takeaway', child: Text('Takeaway')),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                orderType = value ?? orderType;
                                if (orderType != 'dine_in') {
                                  selectedTableId = null;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<dynamic>(
                            value: selectedTableId,
                            decoration: InputDecoration(
                              labelText: 'Table',
                              border: const OutlineInputBorder(),
                              helperText: orderType == 'dine_in'
                                  ? 'Optional'
                                  : 'Only for Dine-In',
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('No Table')),
                              ...tables.map((table) {
                                final value = kIsWeb
                                    ? (table['documentId'] ?? table['id'])
                                    : table['id'];
                                return DropdownMenuItem(
                                  value: value,
                                  child: Text('Table ${table['table_number']}'),
                                );
                              }),
                            ],
                            onChanged: orderType == 'dine_in'
                                ? (value) => setDialogState(
                                    () => selectedTableId = value)
                                : null,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Discount
                    TextFormField(
                      initialValue: discountPercent.toStringAsFixed(1),
                      decoration: const InputDecoration(
                        labelText: 'Discount %',
                        border: OutlineInputBorder(),
                        suffixText: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (v) {
                        final parsed =
                            double.tryParse(v) ?? discountPercent;
                        setDialogState(
                            () => discountPercent = parsed.clamp(0, 100));
                      },
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search items',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),

                    // Items list
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final p = filtered[index];
                            final pid = kIsWeb ? p.documentId : p.id;
                            if (pid == null) return const SizedBox.shrink();

                            final current = qty[pid] ?? 0;

                            final canInc = current < 99;
                            final canDec = current > 0;

                            return ListTile(
                              dense: true,
                              title: Text(p.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                'Price: ${NumberFormat.currency(symbol: 'NPR ').format(p.price)}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700]),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: canDec
                                        ? () => setDialogState(
                                            () => qty[pid] = current - 1)
                                        : null,
                                    icon: const Icon(Icons.remove),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '$current',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: canInc
                                        ? () => setDialogState(
                                            () => qty[pid] = current + 1)
                                        : null,
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Totals (dark numbers)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFEF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          _totalRow('Subtotal', subtotal),
                          _totalRow(
                              'Discount (${discountPercent.toStringAsFixed(1)}%)',
                              -discountAmount),
                          const Divider(),
                          _totalRow('Total', total, isTotal: true),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: hasItems
                                ? () => Navigator.pop(context, true)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.logoPrimary,
                              foregroundColor: AppTheme.logoAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Create Order'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      try {
        // Validate stock for selected items only (fast).
        final selectedEntries = qty.entries.where((e) => e.value > 0).toList();
        final selectedIds = selectedEntries.map((e) => e.key).toList();
        final selectedStock = await ledgerService.getCurrentStockBatch(
            context: context, productIds: selectedIds);
        for (final e in selectedEntries) {
          final available = selectedStock[e.key] ?? 0.0;
          if (e.value > available.floor()) {
            throw Exception(
                'Insufficient stock for ${products.firstWhere((p) => (kIsWeb ? p.documentId : p.id) == e.key).name}. Available: ${available.toStringAsFixed(1)}, Required: ${e.value}');
          }
        }

        final orderId = await _orderService.createOrder(
          dbProvider: dbProvider,
          orderType: orderType,
          tableId: selectedTableId,
          // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
          createdBy: authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
        );

        // Add selected items
        for (final entry in qty.entries) {
          if (entry.value <= 0) continue;
          final product = products.firstWhere((p) {
            final pid = kIsWeb ? p.documentId : p.id;
            return pid == entry.key;
          });
          await _orderService.addItemToOrder(
            dbProvider: dbProvider,
            context: context,
            orderId: orderId,
            product: product,
            quantity: entry.value,
            createdBy: authProvider.currentUserId != null
                ? (kIsWeb
                    ? authProvider.currentUserId!
                    : int.tryParse(authProvider.currentUserId!))
                : null,
          );
        }

        // Apply Discount and force totals update
        await _orderService.updateVATAndDiscount(
          dbProvider: dbProvider,
          orderId: orderId,
          vatPercent: 0.0,
          discountPercent: discountPercent,
        );

        // Await order loading before navigation
        await _loadOrders();

        // UX change: Stay on Orders list (no auto-navigation).
        AppMessenger.showSnackBar(
          'Order placed',
          backgroundColor: Colors.green,
          leadingAssetPath: 'assets/images/order_done.jpg',
          leadingIcon: Icons.receipt_long,
        );
      } catch (e) {
        AppMessenger.showSnackBar('Error creating order: $e',
            backgroundColor: Colors.red);
      }
    }
  }

  Widget _totalRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
            ),
          ),
          Text(
            NumberFormat.currency(symbol: 'NPR ').format(amount),
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
