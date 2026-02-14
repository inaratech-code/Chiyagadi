import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../providers/unified_database_provider.dart';
import '../../services/order_service.dart';
import '../../utils/number_formatter.dart';
import '../../utils/app_messenger.dart';
import '../../models/customer.dart';
import '../dashboard/dashboard_screen.dart';

class OrderPaymentDialog extends StatefulWidget {
  final dynamic orderId; // int (SQLite) or String (Firestore)
  final String orderNumber;
  final double totalAmount;
  final OrderService orderService;

  const OrderPaymentDialog({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.totalAmount,
    required this.orderService,
  });

  @override
  State<OrderPaymentDialog> createState() => _OrderPaymentDialogState();
}

class _OrderPaymentDialogState extends State<OrderPaymentDialog> {
  String _selectedPaymentMethod = 'cash';
  final TextEditingController _amountController = TextEditingController();
  bool _isProcessing = false;
  Customer? _selectedCustomer;

  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _orderItems = [];
  bool _loadingOrder = true;

  double get _subtotal => _orderItems.fold(
      0.0, (sum, item) => sum + ((item['total_price'] as num?)?.toDouble() ?? 0.0));
  double get _discountAmount =>
      (_order?['discount_amount'] as num?)?.toDouble() ?? 0.0;
  double get _displayTotal =>
      (_order?['total_amount'] as num?)?.toDouble() ?? widget.totalAmount;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.totalAmount.toStringAsFixed(2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrderDetails());
  }

  Future<void> _loadOrderDetails() async {
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
      debugPrint('OrderPaymentDialog load order: $e');
    } finally {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 440,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.orderNumber,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[700],
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Scrollable: order details + payment
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Order summary (items, customer, totals)
                    _buildOrderSummary(),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 20),

                    // Payment method
                    Text(
                      'Payment Method',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'cash', label: Text('Cash')),
                        ButtonSegment(value: 'card', label: Text('Card')),
                        ButtonSegment(value: 'digital', label: Text('QR Payment')),
                        ButtonSegment(value: 'credit', label: Text('Credit')),
                      ],
                      selected: {_selectedPaymentMethod},
                      onSelectionChanged: (Set<String> newSelection) async {
                        final next = newSelection.first;
                        if (next == 'credit') {
                          final picked = await _pickCustomer();
                          if (picked == null) return;
                          setState(() {
                            _selectedPaymentMethod = 'credit';
                            _selectedCustomer = picked;
                            _amountController.text = '0';
                          });
                        } else {
                          setState(() {
                            _selectedPaymentMethod = next;
                            if (_selectedPaymentMethod != 'credit') {
                              _selectedCustomer = null;
                              _amountController.text =
                                  widget.totalAmount.toStringAsFixed(2);
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 18),

                    if (_selectedPaymentMethod == 'credit') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person, color: Colors.orange),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _selectedCustomer == null
                                    ? 'Select customer for credit'
                                    : 'Credit customer: ${_selectedCustomer!.name}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: _isProcessing
                                  ? null
                                  : () async {
                                      final picked = await _pickCustomer();
                                      if (picked != null) {
                                        setState(() => _selectedCustomer = picked);
                                      }
                                    },
                              child: Text(
                                  _selectedCustomer == null ? 'Select' : 'Change'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    TextField(
                      controller: _amountController,
                      enabled: !_isProcessing,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: 'Rs. ',
                        hintText: (_selectedPaymentMethod == 'cash' ||
                                _selectedPaymentMethod == 'digital')
                            ? 'Enter full or partial amount'
                            : null,
                        helperText: _selectedPaymentMethod == 'credit'
                            ? 'Enter amount received now (remaining will be credit)'
                            : (_selectedPaymentMethod == 'cash' ||
                                    _selectedPaymentMethod == 'digital')
                                ? 'Partial payment allowed for Cash & QR. Enter less than total; remaining will be due.'
                                : 'Enter amount to pay (partial allowed)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (_selectedPaymentMethod == 'cash' ||
                        _selectedPaymentMethod == 'digital')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _amountController.text =
                                  _displayTotal.toStringAsFixed(2);
                            });
                          },
                          icon: const Icon(Icons.account_balance_wallet,
                              size: 18),
                          label: const Text('Pay Full Amount'),
                        ),
                      ),
                    const SizedBox(height: 22),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isProcessing
                                ? null
                                : () => Navigator.of(context).pop(null),
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    if (_loadingOrder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final customerName =
        (_order?['customer_name'] as String?)?.trim();
    final hasCustomer =
        customerName != null && customerName.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasCustomer) ...[
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customerName!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Items',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
          ),
          const SizedBox(height: 8),
          _orderItems.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No items',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _orderItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = _orderItems[index];
                    final name =
                        item['product_name'] as String? ?? 'Item';
                    final qty =
                        (item['quantity'] as num?)?.toInt() ?? 0;
                    final total = (item['total_price'] as num?)
                            ?.toDouble() ??
                        0.0;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$name × $qty',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          NumberFormatter.formatCurrency(total),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _buildSummaryRow('Subtotal', _subtotal),
          if (_discountAmount > 0)
            _buildSummaryRow('Discount', -_discountAmount),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                NumberFormatter.formatCurrency(_displayTotal),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            NumberFormatter.formatCurrency(amount),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || (_selectedPaymentMethod != 'credit' && amount <= 0)) {
      AppMessenger.showSnackBar('Please enter a valid amount');
      return;
    }

    if (_selectedPaymentMethod == 'credit' && _selectedCustomer == null) {
      AppMessenger.showSnackBar('Please select a customer for credit');
      return;
    }

    if (amount > widget.totalAmount) {
      AppMessenger.showSnackBar('Amount cannot exceed total');
      return;
    }

    // IMPORTANT: Credit means there must be some remaining due (otherwise it's not credit).
    if (_selectedPaymentMethod == 'credit' && amount >= widget.totalAmount) {
      AppMessenger.showSnackBar(
        'For Credit, enter a partial amount less than total (remaining will be credit)',
        backgroundColor: Colors.orange,
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final authProvider =
          Provider.of<InaraAuthProvider>(context, listen: false);
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);

      final createdBy = authProvider.currentUserId != null
          ? (kIsWeb
              ? authProvider.currentUserId!
              : int.tryParse(authProvider.currentUserId!))
          : null;

      final isPartial =
          _selectedPaymentMethod != 'credit' && amount < widget.totalAmount;
      final isCredit = _selectedPaymentMethod == 'credit';
      final creditPaidNow = isCredit ? amount : 0.0;

      await widget.orderService.completePayment(
        dbProvider: dbProvider,
        context: context,
        orderId: widget.orderId,
        paymentMethod: _selectedPaymentMethod,
        amount: isCredit ? creditPaidNow : amount,
        customerId: _selectedCustomer == null
            ? null
            : (kIsWeb
                ? (_selectedCustomer!.documentId ??
                    _selectedCustomer!.id?.toString())
                : _selectedCustomer!.id),
        partialAmount: isCredit
            ? (creditPaidNow > 0 ? creditPaidNow : null)
            : (isPartial ? amount : null),
        createdBy: createdBy,
      );

      // NEW: Refresh dashboard to update sales and credit immediately
      DashboardScreen.refreshDashboard();

      if (mounted) {
        if (_selectedPaymentMethod == 'credit') {
          AppMessenger.showSnackBar(
            'Credit saved for ${_selectedCustomer?.name ?? 'customer'}',
            backgroundColor: Colors.orange,
            leadingAssetPath: 'assets/images/order_done.jpg',
            leadingIcon: Icons.receipt_long,
          );
        } else {
          AppMessenger.showSnackBar(
            'Payment done',
            backgroundColor: Colors.green,
            leadingAssetPath: 'assets/images/payment_done.jpg',
            leadingIcon: Icons.check_circle,
          );
        }
        Navigator.of(context).pop({'success': true});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppMessenger.showSnackBar('Error: $e', backgroundColor: Colors.red);
      }
    }
  }

  Future<Customer?> _pickCustomer() async {
    final dbProvider =
        Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    await dbProvider.init();

    List<Customer> customers = [];

    Future<void> reloadCustomers(
        {void Function(void Function())? setDialogState}) async {
      // PERF: Keep the payment dialog snappy on large customer lists.
      final all = await dbProvider.query('customers', limit: 500);
      final list = all.map((m) => Customer.fromMap(m)).toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      customers = list;
      setDialogState?.call(() {});
    }

    await reloadCustomers();

    final search = TextEditingController();

    final result = await showDialog<Customer?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = search.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? customers
              : customers.where((c) {
                  final phone = (c.phone ?? '').toLowerCase();
                  return c.name.toLowerCase().contains(q) || phone.contains(q);
                }).toList();

          return AlertDialog(
            title: const Text('Select Customer'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name / phone',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Text('No customers found'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final c = filtered[index];
                              return ListTile(
                                title: Text(c.name),
                                subtitle:
                                    c.phone != null ? Text(c.phone!) : null,
                                trailing: Text(
                                  'Bal: ${NumberFormatter.formatCurrency(c.creditBalance)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                onTap: () => Navigator.pop(context, c),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final created = await _createCustomerInline(dbProvider);
                  if (created == null) return;
                  // Refresh list and auto-select the newly created customer.
                  await reloadCustomers(setDialogState: setDialogState);
                  Navigator.pop(context, created);
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Add Customer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );

    search.dispose();
    return result;
  }

  Future<Customer?> _createCustomerInline(
      UnifiedDatabaseProvider dbProvider) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Customer'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true) {
      nameController.dispose();
      phoneController.dispose();
      return null;
    }

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();

    if (name.isEmpty) {
      AppMessenger.showSnackBar('Customer name is required');
      return null;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await dbProvider.insert('customers', {
        'name': name,
        'phone': phone.isEmpty ? null : phone,
        'email': null,
        'address': null,
        'credit_limit': 0.0,
        'credit_balance': 0.0,
        'notes': null,
        'created_at': now,
        'updated_at': now,
        'synced': 0,
      });

      // Load back the customer for correct ID/documentId handling
      final rows = await dbProvider.query(
        'customers',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        // Fallback: construct a Customer object
        return Customer(
          id: kIsWeb ? null : (id is int ? id : int.tryParse(id.toString())),
          documentId: kIsWeb ? id.toString() : null,
          name: name,
          phone: phone.isEmpty ? null : phone,
          creditLimit: 0,
          creditBalance: 0,
          createdAt: now,
          updatedAt: now,
        );
      }
      return Customer.fromMap(rows.first);
    } catch (e) {
      AppMessenger.showSnackBar('Error adding customer: $e',
          backgroundColor: Colors.red);
      return null;
    }
  }
}
