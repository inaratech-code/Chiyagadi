import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../models/product.dart';
import '../../services/order_service.dart';
import '../../services/inventory_ledger_service.dart';
import '../../utils/theme.dart';
import 'package:intl/intl.dart';
import '../dashboard/dashboard_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final dynamic orderId; // Can be int (SQLite) or String (Firestore)
  final String orderNumber;
  final bool
      autoOpenAddItems; // opens multi-add on first load if order is empty

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
    this.autoOpenAddItems = false,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final OrderService _orderService = OrderService();
  List<Map<String, dynamic>> _orderItems = [];
  Map<String, dynamic>? _order;
  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = false;
  final TextEditingController _discountController = TextEditingController();
  bool _didAutoOpenAddItems = false;

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Load order - FIXED: Handle both SQLite (id) and Firestore (documentId) queries
      final orders = await dbProvider.query(
        'orders',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [widget.orderId],
      );
      if (orders.isNotEmpty) {
        _order = orders.first;
        // Initialize Discount controller
        _discountController.text =
            (_order!['discount_percent'] as num? ?? 0.0).toStringAsFixed(1);

        // Ensure totals are recalculated
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        // Trigger recalculation by updating Discount with current values
        await _orderService.updateVATAndDiscount(
          dbProvider: dbProvider,
          orderId: widget.orderId,
          vatPercent: 0.0,
          discountPercent:
              (_order!['discount_percent'] as num?)?.toDouble() ?? 0.0,
        );
        // Reload to get updated values
        final updatedOrders = await dbProvider.query(
          'orders',
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [widget.orderId],
        );
        if (updatedOrders.isNotEmpty) {
          setState(() {
            _order = updatedOrders.first;
          });
        }
      }

      // Load order items
      _orderItems = await dbProvider.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [widget.orderId],
      );

      // Load products - only sellable items for orders
      // FIXED: Handle Firestore query limitations (no OR with IS NULL)
      List<Map<String, dynamic>> productMaps;
      if (kIsWeb) {
        // For Firestore: Query all active products, filter in memory
        final allProducts = await dbProvider.query(
          'products',
          where: 'is_active = ?',
          whereArgs: [1],
        );
        productMaps = allProducts.where((p) {
          final isSellable = p['is_sellable'];
          // Include if is_sellable is 1, null, or not set (default to sellable)
          return isSellable == null || isSellable == 1;
        }).toList();
      } else {
        // For SQLite: Can use OR clause
        productMaps = await dbProvider.query(
          'products',
          where: 'is_active = ? AND (is_sellable = ? OR is_sellable IS NULL)',
          whereArgs: [1, 1],
        );
      }
      _products = productMaps.map((map) => Product.fromMap(map)).toList();
      debugPrint('Loaded ${_products.length} products for order');

      // Load categories
      _categories =
          await dbProvider.query('categories', orderBy: 'display_order ASC');
      debugPrint('Loaded ${_categories.length} categories');
    } catch (e) {
      debugPrint('Error loading order data: $e');
    } finally {
      setState(() => _isLoading = false);

      // Auto-open multi-add once for empty orders (fast order creation flow)
      if (mounted &&
          widget.autoOpenAddItems &&
          !_didAutoOpenAddItems &&
          _orderItems.isEmpty) {
        _didAutoOpenAddItems = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showAddMultipleItemsDialog();
        });
      }
    }
  }

  double get _subtotal {
    // FIXED: Calculate from order items, or use order's subtotal if available
    final calculatedSubtotal = _orderItems.fold(
        0.0, (sum, item) => sum + (item['total_price'] as num).toDouble());
    final orderSubtotal = (_order?['subtotal'] as num?)?.toDouble();
    return orderSubtotal ?? calculatedSubtotal;
  }

  double get _discountAmount {
    return (_order?['discount_amount'] as num?)?.toDouble() ?? 0.0;
  }

  double get _total {
    // Calculate total from subtotal and discount
    final orderTotal = (_order?['total_amount'] as num?)?.toDouble();
    if (orderTotal != null && orderTotal > 0) {
      return orderTotal;
    }
    // Calculate: Subtotal - Discount
    final subtotal = _subtotal;
    final discount = _discountAmount;
    return subtotal - discount;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Order ${widget.orderNumber}'),
        ),
        actions: [
          // Only show delete/cancel if order is not paid
          if (_order?['payment_status'] != 'paid') ...[
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.orange),
              onPressed: () => _cancelOrder(),
              tooltip: 'Cancel Order',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteOrder(),
              tooltip: 'Delete Order',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddItemDialog(),
            tooltip: 'Add Item',
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: () => _showAddMultipleItemsDialog(),
            tooltip: 'Add Multiple Items',
          ),
        ],
      ),
      body: _isLoading || _order == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Order Info Card
                  Card(
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Order ${widget.orderNumber}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  _order?['status'] as String? ?? 'pending',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                backgroundColor:
                                    AppTheme.warningColor.withOpacity(0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                              'Type: ${_order?['order_type'] == 'dine_in' ? 'Dine-In' : 'Takeaway'}'),
                          Text(
                              'Payment: ${_order?['payment_status'] == 'paid' ? 'Paid' : 'Unpaid'}'),
                        ],
                      ),
                    ),
                  ),

                  // Items List
                  _orderItems.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_outlined,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No items in order',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _showAddMultipleItemsDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Items'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _orderItems.length,
                          itemBuilder: (context, index) {
                            final item = _orderItems[index];
                            // FIXED: Handle both int (SQLite) and String (Firestore) product IDs
                            final productId = item['product_id'];
                            final product = _products.firstWhere(
                              (p) {
                                final pId = kIsWeb ? p.documentId : p.id;
                                return pId == productId;
                              },
                              orElse: () => Product(
                                categoryId: 0,
                                name: 'Unknown Product',
                                price: 0,
                                createdAt: 0,
                                updatedAt: 0,
                              ),
                            );
                            return _buildOrderItemCard(item, product);
                          },
                        ),

                  // Totals and Payment
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // VAT and Discount Input Fields
                        if (_order?['payment_status'] != 'paid') ...[
                          TextField(
                            controller: _discountController,
                            decoration: InputDecoration(
                              labelText: 'Discount %',
                              border: const OutlineInputBorder(),
                              suffixText: '%',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                            onChanged: (value) => _updateVATAndDiscount(),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Breakdown: Subtotal, Discount, Total
                        _buildTotalRow('Subtotal', _subtotal),
                        // Always show discount if percent is set (even if 0, show it)
                        if ((_order?['discount_percent'] as num?) != null)
                          _buildTotalRow(
                            'Discount (${(_order?['discount_percent'] as num? ?? 0).toStringAsFixed(1)}%)',
                            -_discountAmount,
                          ),
                        const Divider(),
                        _buildTotalRow('Total Payable', _total, isTotal: true),
                        const SizedBox(height: 16),

                        // Payment Status
                        Builder(
                          builder: (context) {
                            final paymentStatus =
                                _order?['payment_status'] as String? ??
                                    'unpaid';
                            final creditAmount =
                                (_order?['credit_amount'] as num? ?? 0)
                                    .toDouble();
                            final paidAmount =
                                (_order?['paid_amount'] as num? ?? 0)
                                    .toDouble();

                            if (paymentStatus == 'paid') {
                              return Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.successColor
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppTheme.successColor),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: AppTheme.successColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          'PAID - ${_getPaymentMethodLabel(_order?['payment_method'] as String? ?? 'cash')}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.successColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _printBill(),
                                          icon: const Icon(Icons.print),
                                          label: const Text('Print'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _shareBill(),
                                          icon: const Icon(Icons.share),
                                          label: const Text('Share'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            } else if (paymentStatus == 'partial' ||
                                creditAmount > 0) {
                              return Column(
                                children: [
                                  // Partial payment or credit status
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningColor
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppTheme.warningColor),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.account_balance_wallet,
                                                color: AppTheme.warningColor),
                                            const SizedBox(width: 8),
                                            Text(
                                              creditAmount > 0
                                                  ? 'CREDIT / PARTIAL'
                                                  : 'PARTIAL PAYMENT',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.warningColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (paidAmount > 0) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'Paid: ${NumberFormat.currency(symbol: 'NPR ').format(paidAmount)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppTheme.successColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        if (creditAmount > 0) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Credit: ${NumberFormat.currency(symbol: 'NPR ').format(creditAmount)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (creditAmount > 0) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () =>
                                            _showPayCreditDialog(creditAmount),
                                        icon: const Icon(Icons.payment),
                                        label: Text(
                                            'Pay Credit (${NumberFormat.currency(symbol: 'NPR ').format(creditAmount)})'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _printBill(),
                                          icon: const Icon(Icons.print),
                                          label: const Text('Print'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _shareBill(),
                                          icon: const Icon(Icons.share),
                                          label: const Text('Share'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            } else {
                              return Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _orderItems.isEmpty
                                          ? null
                                          : () => _showPaymentDialog(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Theme.of(context).primaryColor,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text(
                                        'Complete Payment',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderItemCard(Map<String, dynamic> item, Product product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildVegNonVegIcon(product),
        title: Text(
          product.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${NumberFormat.currency(symbol: 'NPR ').format(item['unit_price'])} × ${item['quantity']}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            if (product.description != null &&
                product.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                product.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  NumberFormat.currency(symbol: 'NPR ')
                      .format(item['total_price']),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFFFFC107),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: product.isVeg ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    product.isVeg ? 'VEG' : 'NON-VEG',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              // FIXED: Handle both int (SQLite) and String (Firestore) order item IDs
              onPressed: () => _removeItem(item['id']),
              tooltip: 'Remove item',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVegNonVegIcon(Product product) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: product.isVeg
            ? AppTheme.successColor.withOpacity(0.2)
            : AppTheme.errorColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          product.isVeg ? 'V' : 'N',
          style: TextStyle(
            color: product.isVeg ? AppTheme.successColor : AppTheme.errorColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
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
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            NumberFormat.currency(symbol: 'NPR ').format(amount),
            style: TextStyle(
              fontSize: isTotal ? 20 : 16,
              fontWeight: FontWeight.bold,
              // User request: amounts should be dark for readability
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemDialog() async {
    // FIXED: Handle both int (SQLite) and String (Firestore) category IDs
    // Use Object? instead of dynamic to avoid type inference issues
    Object? selectedCategoryId;
    List<Product> filteredProducts = _products;
    Product? selectedProduct;
    int quantity = 1;
    double? availableStock; // Track available stock for selected product
    final InventoryLedgerService ledgerService =
        InventoryLedgerService(); // For stock checking

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Item to Order',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Category Filter
                // FIXED: Use Object? to handle both int and String IDs without type errors
                DropdownButtonFormField<Object?>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<Object?>(
                        value: null, child: Text('All Categories')),
                    ..._categories.map((cat) {
                      // FIXED: Handle both int (SQLite) and String (Firestore) IDs
                      // Explicitly convert to Object? to avoid type inference issues
                      final catIdData = cat['id'];
                      final catId = catIdData is int
                          ? catIdData as Object?
                          : (catIdData is String
                              ? catIdData as Object?
                              : catIdData);
                      return DropdownMenuItem<Object?>(
                        value: catId,
                        child: Text(cat['name'] as String),
                      );
                    }),
                  ],
                  onChanged: (Object? value) {
                    setDialogState(() {
                      // FIXED: Explicitly handle Object? type - no type checking
                      selectedCategoryId = value;
                      // FIXED: Compare category IDs safely, handling null and different types
                      if (value == null) {
                        // Show all products when "All Categories" is selected
                        filteredProducts = _products;
                      } else {
                        // Filter products by category
                        filteredProducts = _products.where((p) {
                          // Handle null category IDs - include products without category when filtering
                          if (p.categoryId == null) {
                            // Option: include products without category, or exclude them
                            // For now, exclude products without category when a specific category is selected
                            return false;
                          }
                          // Compare as strings to handle both int and String IDs
                          final pCategoryId = p.categoryId.toString();
                          final selectedId = value.toString();
                          return pCategoryId == selectedId;
                        }).toList();
                      }
                      // Reset product selection when category changes
                      selectedProduct = null;
                    });
                  },
                ),

                const SizedBox(height: 16),

                // Product Selection
                // FIXED: Handle both int (SQLite) and String (Firestore) product IDs
                filteredProducts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text(
                              'No products available in this category',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  selectedCategoryId = null;
                                  filteredProducts = _products;
                                  selectedProduct = null;
                                });
                              },
                              child: const Text('Show All Products'),
                            ),
                          ],
                        ),
                      )
                    : DropdownButtonFormField<Object?>(
                        value: kIsWeb
                            ? selectedProduct?.documentId
                            : selectedProduct?.id,
                        decoration: const InputDecoration(
                          labelText: 'Select Product *',
                          border: OutlineInputBorder(),
                        ),
                        items: filteredProducts.map((product) {
                          final productId =
                              kIsWeb ? product.documentId : product.id;
                          return DropdownMenuItem<Object?>(
                            value: productId,
                            child: Text(
                                '${product.name} - ${NumberFormat.currency(symbol: 'NPR ').format(product.price)}'),
                          );
                        }).toList(),
                        onChanged: (Object? value) async {
                          if (value != null) {
                            try {
                              final product = filteredProducts.firstWhere((p) {
                                final pId = kIsWeb ? p.documentId : p.id;
                                return pId == value;
                              });
                              setDialogState(() {
                                selectedProduct = product;
                              });

                              // Load stock availability for selected product
                              final productId =
                                  kIsWeb ? product.documentId : product.id;
                              if (productId != null) {
                                try {
                                  final stock =
                                      await ledgerService.getCurrentStock(
                                    context: context,
                                    productId: productId,
                                  );
                                  // Get current quantity already in this order
                                  final dbProvider =
                                      Provider.of<UnifiedDatabaseProvider>(
                                          context,
                                          listen: false);
                                  await dbProvider.init();
                                  final existingItems = await dbProvider.query(
                                    'order_items',
                                    where: 'order_id = ? AND product_id = ?',
                                    whereArgs: [widget.orderId, productId],
                                  );
                                  double currentOrderQty = 0.0;
                                  if (existingItems.isNotEmpty) {
                                    currentOrderQty = (existingItems
                                                .first['quantity'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                  }
                                  final maxAvailable =
                                      (stock - currentOrderQty).toInt();

                                  setDialogState(() {
                                    availableStock = stock;
                                    // Limit quantity to available stock
                                    if (quantity > maxAvailable &&
                                        maxAvailable > 0) {
                                      quantity = maxAvailable;
                                    } else if (maxAvailable <= 0) {
                                      quantity = 0;
                                    } else if (quantity == 0 &&
                                        maxAvailable > 0) {
                                      quantity = 1; // Set to 1 if was 0
                                    }
                                  });
                                } catch (e) {
                                  debugPrint('Error loading stock: $e');
                                  setDialogState(() {
                                    availableStock = null;
                                  });
                                }
                              }
                            } catch (e) {
                              debugPrint('Error finding product: $e');
                              setDialogState(() {
                                selectedProduct = null;
                                availableStock = null;
                              });
                            }
                          } else {
                            setDialogState(() {
                              selectedProduct = null;
                              availableStock = null;
                            });
                          }
                        },
                      ),

                const SizedBox(height: 16),

                // Stock availability info
                if (selectedProduct != null && availableStock != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          availableStock! > 0
                              ? Icons.check_circle
                              : Icons.warning,
                          color: availableStock! > 0
                              ? Colors.green
                              : Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Available Stock: ${availableStock!.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: availableStock! > 0
                                ? Colors.green
                                : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Quantity
                Row(
                  children: [
                    const Text('Quantity: '),
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: quantity > 1
                          ? () {
                              setDialogState(() => quantity--);
                            }
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '$quantity',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: (availableStock != null &&
                                  quantity > availableStock!)
                              ? Colors.red
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        if (selectedProduct != null) {
                          final productId = kIsWeb
                              ? selectedProduct!.documentId
                              : selectedProduct!.id;
                          if (productId != null && availableStock != null) {
                            // Get current quantity in order
                            final dbProvider =
                                Provider.of<UnifiedDatabaseProvider>(context,
                                    listen: false);
                            await dbProvider.init();
                            final existingItems = await dbProvider.query(
                              'order_items',
                              where: 'order_id = ? AND product_id = ?',
                              whereArgs: [widget.orderId, productId],
                            );
                            double currentOrderQty = 0.0;
                            if (existingItems.isNotEmpty) {
                              currentOrderQty =
                                  (existingItems.first['quantity'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                            }
                            final maxQty =
                                (availableStock! - currentOrderQty).toInt();

                            setDialogState(() {
                              if (quantity < maxQty) {
                                quantity++;
                              }
                            });
                          } else {
                            setDialogState(() => quantity++);
                          }
                        } else {
                          setDialogState(() => quantity++);
                        }
                      },
                    ),
                  ],
                ),

                const Spacer(),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: selectedProduct == null
                          ? null
                          : () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && selectedProduct != null) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final auth = Provider.of<InaraAuthProvider>(context, listen: false);
        final createdBy = auth.currentUserId != null
            ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
            : null;
        await _orderService.addItemToOrder(
          dbProvider: dbProvider,
          context: context,
          orderId: widget.orderId,
          product: selectedProduct!,
          quantity: quantity,
          createdBy: createdBy,
        );
        await _loadData(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item added to order'),
              backgroundColor: Colors.green,
            ),
          );
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

  Future<void> _showAddMultipleItemsDialog() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Batch-load stock for all sellable products to keep UI fast
      final productIds = _products
          .map((p) => kIsWeb ? p.documentId : p.id)
          .where((id) => id != null)
          .toList()
          .cast<dynamic>();

      final ledgerService = InventoryLedgerService();
      final stockMap = await ledgerService.getCurrentStockBatch(
        context: context,
        productIds: productIds,
      );

      final searchController = TextEditingController();
      final Map<dynamic, int> qty = {};

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = _products.where((p) {
              if (query.isEmpty) return true;
              return p.name.toLowerCase().contains(query);
            }).toList();

            return AlertDialog(
              title: const Text('Add Items'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search items',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final pid = kIsWeb ? p.documentId : p.id;
                          if (pid == null) return const SizedBox.shrink();

                          final available = stockMap[pid] ?? 0.0;
                          final current = qty[pid] ?? 0;
                          final maxQty = available.floor();
                          final canAddMore = current < maxQty;

                          return ListTile(
                            dense: true,
                            title: Text(p.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              'Stock: ${available.toStringAsFixed(1)} • Price: ${NumberFormat.currency(symbol: 'NPR ').format(p.price)}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700]),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  onPressed: current > 0
                                      ? () => setDialogState(
                                          () => qty[pid] = current - 1)
                                      : null,
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
                                  icon: const Icon(Icons.add),
                                  onPressed: canAddMore
                                      ? () => setDialogState(
                                          () => qty[pid] = current + 1)
                                      : null,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
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
                  onPressed: qty.values.any((v) => v > 0)
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Add Selected'),
                ),
              ],
            );
          },
        ),
      );

      if (confirmed != true) return;

      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      final createdBy = auth.currentUserId != null
          ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
          : null;

      for (final entry in qty.entries) {
        if (entry.value <= 0) continue;
        final product = _products.firstWhere((p) {
          final pid = kIsWeb ? p.documentId : p.id;
          return pid == entry.key;
        });

        await _orderService.addItemToOrder(
          dbProvider: dbProvider,
          context: context,
          orderId: widget.orderId,
          product: product,
          quantity: entry.value,
          createdBy: createdBy,
        );
      }

      await _loadData();
    } catch (e) {
      debugPrint('Error adding multiple items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // FIXED: Handle both int (SQLite) and String (Firestore) order item IDs
  Future<void> _removeItem(dynamic itemId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item?'),
        content: const Text(
            'Are you sure you want to remove this item from the order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
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
        await _loadData(); // Await to ensure data is loaded
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _updateVATAndDiscount() async {
    final discountPercent = double.tryParse(_discountController.text) ?? 0.0;

    if (discountPercent < 0 || discountPercent > 100) return;

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);

      // Calculate values locally for immediate UI update
      final subtotal = _subtotal;
      final discountAmount = subtotal * (discountPercent / 100);
      final totalAmount = subtotal - discountAmount;

      // Update local state immediately (no page refresh)
      setState(() {
        if (_order != null) {
          _order!['tax_percent'] = 0.0;
          _order!['tax_amount'] = 0.0;
          _order!['discount_percent'] = discountPercent;
          _order!['discount_amount'] = discountAmount;
          _order!['total_amount'] = totalAmount;
          _order!['subtotal'] = subtotal;
        }
      });

      // Update database in background (don't wait for it to complete)
      _orderService
          .updateVATAndDiscount(
        dbProvider: dbProvider,
        orderId: widget.orderId,
        vatPercent: 0.0,
        discountPercent: discountPercent,
      )
          .catchError((e) {
        debugPrint('Error updating Discount in database: $e');
        // Reload data if update fails to sync with database
        _loadData();
      });
    } catch (e) {
      debugPrint('Error updating Discount: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        // Reload data on error
        _loadData();
      }
    }
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order?'),
        content: const Text(
            'Are you sure you want to cancel this order? The order status will be changed to "cancelled".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await _orderService.cancelOrder(dbProvider, widget.orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order cancelled successfully'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context, true); // Return to orders list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error cancelling order: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteOrder() async {
    // NEW: Role-based + password-protected deletion
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final pinController = TextEditingController();
    bool obscurePassword = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete Order (Password Required)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Deleting an order is a sensitive action and requires password confirmation.'),
              const SizedBox(height: 12),
              TextField(
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
                    tooltip:
                        obscurePassword ? 'Show password' : 'Hide password',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final pin = pinController.text.trim();
                final valid = await auth.verifyAdminPin(pin);
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Order?'),
        content: const Text(
            'Are you sure you want to permanently delete this order? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await _orderService.deleteOrder(
          dbProvider: dbProvider,
          context: context,
          orderId: widget.orderId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Return to orders list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting order: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _printBill() async {
    // TODO: Implement print functionality
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Print functionality coming soon')),
      );
    }
  }

  Future<void> _shareBill() async {
    // TODO: Implement share functionality (PDF/WhatsApp)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Share functionality coming soon')),
      );
    }
  }

  Future<void> _showPaymentDialog() async {
    String paymentMethod = 'cash';
    int? selectedCustomerId;
    List<Map<String, dynamic>> customers = [];
    final partialAmountController = TextEditingController();
    bool allowPartial = false;

    // Load customers for credit payment
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      customers = await dbProvider.query('customers', orderBy: 'name ASC');
    } catch (e) {
      debugPrint('Error loading customers: $e');
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Complete Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total Amount: ${NumberFormat.currency(symbol: 'NPR ').format(_total)}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Select Payment Method:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: const Row(
                  children: [
                    Icon(Icons.money, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Cash'),
                  ],
                ),
                value: 'cash',
                groupValue: paymentMethod,
                onChanged: (value) {
                  setDialogState(() {
                    paymentMethod = value!;
                    selectedCustomerId = null;
                    allowPartial = false;
                  });
                },
              ),
              RadioListTile<String>(
                title: const Row(
                  children: [
                    Icon(Icons.qr_code, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('QR Payment'),
                  ],
                ),
                value: 'digital',
                groupValue: paymentMethod,
                onChanged: (value) {
                  setDialogState(() {
                    paymentMethod = value!;
                    selectedCustomerId = null;
                    allowPartial = false;
                  });
                },
              ),
              CheckboxListTile(
                title: const Text('Allow Partial Payment'),
                value: allowPartial,
                onChanged: paymentMethod != 'credit'
                    ? (value) {
                        setDialogState(() {
                          allowPartial = value ?? false;
                          if (!allowPartial) {
                            selectedCustomerId = null;
                          }
                        });
                      }
                    : null,
                subtitle: paymentMethod != 'credit'
                    ? const Text(
                        'Pay less than total amount (requires customer)')
                    : null,
              ),
              if (allowPartial && paymentMethod != 'credit') ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Select Customer for Credit:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: customers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                              'No customers found. Please add a customer first.'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            return RadioListTile<int>(
                              title: Text(customer['name'] as String),
                              value: customer['id'] as int,
                              groupValue: selectedCustomerId,
                              onChanged: (value) {
                                setDialogState(
                                    () => selectedCustomerId = value);
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: partialAmountController,
                  decoration: InputDecoration(
                    labelText: 'Amount to Pay (NPR)',
                    hintText:
                        'Enter amount less than ${NumberFormat.currency(symbol: 'NPR ').format(_total)}',
                    border: const OutlineInputBorder(),
                    prefixText: 'NPR ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, size: 16, color: AppTheme.warningColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Remaining amount will be saved as credit',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.warningColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              RadioListTile<String>(
                title: const Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Credit Payment'),
                  ],
                ),
                value: 'credit',
                groupValue: paymentMethod,
                onChanged: (value) {
                  setDialogState(() => paymentMethod = value!);
                },
              ),
              if (paymentMethod == 'credit') ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Select Customer:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: customers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                              'No customers found. Please add a customer first.'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            final creditBalance =
                                (customer['credit_balance'] as num? ?? 0)
                                    .toDouble();
                            final creditLimit =
                                (customer['credit_limit'] as num? ?? 0)
                                    .toDouble();
                            final available = creditLimit - creditBalance;

                            return RadioListTile<int>(
                              title: Text(customer['name'] as String),
                              subtitle: Text(
                                'Available: ${NumberFormat.currency(symbol: 'NPR ').format(available)}',
                                style: TextStyle(
                                  color: available >= _total
                                      ? Colors.green
                                      : Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                              value: customer['id'] as int,
                              groupValue: selectedCustomerId,
                              onChanged: available >= _total
                                  ? (value) {
                                      setDialogState(
                                          () => selectedCustomerId = value);
                                    }
                                  : null,
                            );
                          },
                        ),
                ),
                if (selectedCustomerId != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info,
                            size: 16, color: AppTheme.warningColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Credit will be deducted from customer account',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.warningColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (paymentMethod == 'credit' &&
                          selectedCustomerId == null) ||
                      (allowPartial &&
                          (selectedCustomerId == null ||
                              partialAmountController.text.isEmpty ||
                              double.tryParse(partialAmountController.text) ==
                                  null ||
                              double.parse(partialAmountController.text) <= 0 ||
                              double.parse(partialAmountController.text) >
                                  _total))
                  ? null
                  : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Complete Payment'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        final authProvider =
            Provider.of<InaraAuthProvider>(context, listen: false);

        // Calculate payment amounts
        double? partialAmount;
        int? customerId;

        if (allowPartial && partialAmountController.text.isNotEmpty) {
          partialAmount = double.tryParse(partialAmountController.text);
          if (partialAmount == null ||
              partialAmount <= 0 ||
              partialAmount > _total) {
            throw Exception('Invalid partial amount');
          }
          if (selectedCustomerId == null) {
            throw Exception('Please select a customer for partial payment');
          }
          customerId = selectedCustomerId;
        } else if (paymentMethod == 'credit') {
          customerId = selectedCustomerId;
        }

        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await _orderService.completePayment(
          dbProvider: dbProvider,
          context: context,
          orderId: widget.orderId,
          paymentMethod: paymentMethod,
          amount: _total,
          customerId: customerId,
          partialAmount: partialAmount,
          // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
          createdBy: authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
        );

        // NEW: Refresh dashboard to update sales and credit immediately
        DashboardScreen.refreshDashboard();

        await _loadData(); // Await to ensure data is loaded

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                paymentMethod == 'credit'
                    ? 'Payment completed via Credit'
                    : paymentMethod == 'cash'
                        ? 'Payment completed via Cash'
                        : 'Payment completed via QR Payment',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate back immediately
          if (mounted) {
            Navigator.pop(context);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _getPaymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'Cash';
      case 'digital':
        return 'QR Payment';
      case 'credit':
        return 'Credit';
      default:
        return method ?? 'Cash';
    }
  }

  Future<void> _showPayCreditDialog(double creditAmount) async {
    final amountController =
        TextEditingController(text: creditAmount.toStringAsFixed(2));
    String paymentMethod = 'cash';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pay Credit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Outstanding Credit: ${NumberFormat.currency(symbol: 'NPR ').format(creditAmount)}'),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount to Pay (NPR)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              const Text('Payment Method:'),
              RadioListTile<String>(
                title: const Text('Cash'),
                value: 'cash',
                groupValue: paymentMethod,
                onChanged: (value) =>
                    setDialogState(() => paymentMethod = value!),
              ),
              RadioListTile<String>(
                title: const Text('QR Payment'),
                value: 'digital',
                groupValue: paymentMethod,
                onChanged: (value) =>
                    setDialogState(() => paymentMethod = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pay Credit'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        final amount = double.tryParse(amountController.text);
        if (amount == null || amount <= 0 || amount > creditAmount) {
          throw Exception('Invalid amount');
        }

        final authProvider =
            Provider.of<InaraAuthProvider>(context, listen: false);
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await _orderService.payCredit(
          dbProvider: dbProvider,
          orderId: widget.orderId,
          amount: amount,
          paymentMethod: paymentMethod,
          // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
          createdBy: authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
        );

        await _loadData(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Credit payment of ${NumberFormat.currency(symbol: 'NPR ').format(amount)} recorded'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }
}
