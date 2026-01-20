import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/customer.dart';
import '../../utils/theme.dart';
import '../orders/order_detail_screen.dart';

class CustomersScreen extends StatefulWidget {
  final bool hideAppBar;
  const CustomersScreen({super.key, this.hideAppBar = false});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _customers = [];
  List<Map<String, dynamic>> _creditTransactions = [];
  bool _isLoading = true;
  dynamic _selectedCustomerId;
  String _viewMode = 'list'; // 'list' or 'credits'
  int _customersLimit = 200;
  bool _canLoadMoreCustomers = false;

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomers());
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final maps = await dbProvider.query(
        'customers',
        orderBy: 'name ASC',
        limit: _customersLimit,
      );
      _customers = maps.map((map) => Customer.fromMap(map)).toList();
      _canLoadMoreCustomers = maps.length >= _customersLimit;
    } catch (e) {
      debugPrint('Error loading customers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCreditTransactions(dynamic customerId) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      _creditTransactions = await dbProvider.query(
        'credit_transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at DESC',
      );
      setState(() {});
    } catch (e) {
      debugPrint('Error loading credit transactions: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadCustomerOrders(
      dynamic customerId) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      return await dbProvider.query(
        'orders',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      debugPrint('Error loading customer orders: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Customer Credits'),
              actions: [
                IconButton(
                  icon: Icon(_viewMode == 'list'
                      ? Icons.account_balance_wallet
                      : Icons.list),
                  onPressed: () {
                    setState(() {
                      _viewMode = _viewMode == 'list' ? 'credits' : 'list';
                      if (_viewMode == 'list') {
                        _selectedCustomerId = null;
                      }
                    });
                  },
                  tooltip: _viewMode == 'list' ? 'View Credits' : 'View List',
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showAddCustomerDialog(),
                  tooltip: 'Add Customer',
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _viewMode == 'list'
              ? _buildCustomersList()
              : _buildCreditsView(),
      floatingActionButton: _viewMode == 'list' && _customers.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddCustomerDialog(),
              backgroundColor: AppTheme.logoPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Add Customer'),
            )
          : null,
    );
  }

  Widget _buildCustomersList() {
    return _customers.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No customers found',
                    style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _showAddCustomerDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Customer'),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _customers.length + (_canLoadMoreCustomers ? 1 : 0),
            itemBuilder: (context, index) {
              if (_canLoadMoreCustomers && index == _customers.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _customersLimit += 200;
                      });
                      _loadCustomers();
                    },
                    child: const Text('Load more'),
                  ),
                );
              }
              final customer = _customers[index];
              final hasCredit = customer.creditBalance > 0;
              final brand = AppTheme.logoPrimary;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                // Keep UI clean/neutral; use brand color only as subtle accents.
                color: hasCredit ? brand.withOpacity(0.04) : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: brand,
                    child: Text(
                      customer.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(customer.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (customer.phone != null)
                        Text('Phone: ${customer.phone}'),
                      Text(
                        'Credit: ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditBalance)} / ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditLimit)}',
                        style: TextStyle(
                          color: hasCredit ? brand : Colors.grey[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasCredit)
                        Chip(
                          label: Text(
                            'Credit',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: brand,
                            ),
                          ),
                          side: BorderSide(color: brand.withOpacity(0.35)),
                          backgroundColor: Colors.white,
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditCustomerDialog(customer),
                      ),
                      IconButton(
                        icon: const Icon(Icons.account_balance_wallet),
                        onPressed: () {
                          final customerId = customer.documentId ?? customer.id;
                          setState(() {
                            _selectedCustomerId = customerId;
                            _viewMode = 'credits';
                          });
                          if (customerId != null) {
                            _loadCreditTransactions(customerId);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Widget _buildCreditsView() {
    if (_selectedCustomerId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Select a customer to view credit details',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _viewMode = 'list';
                  _selectedCustomerId = null;
                });
              },
              child: const Text('Back to Customers'),
            ),
          ],
        ),
      );
    }

    // FIXED: Handle "Bad state: No element" error
    final customer = _customers.firstWhere(
      (c) {
        final cId = kIsWeb ? (c.documentId ?? c.id) : c.id;
        return cId == _selectedCustomerId ||
            cId.toString() == _selectedCustomerId.toString();
      },
      orElse: () => _customers.first, // Fallback to first customer if not found
    );

    return Column(
      children: [
        // Customer Summary Card
        Card(
          margin: const EdgeInsets.all(16),
          color: customer.creditBalance > 0
              ? const Color(0xFFFF6B6B).withOpacity(0.1)
              : const Color(0xFF00B894).withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      customer.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _selectedCustomerId = null;
                          _viewMode = 'list';
                        });
                      },
                    ),
                  ],
                ),
                if (customer.phone != null) Text('Phone: ${customer.phone}'),
                const Divider(),
                // Enhanced Summary Cards
                Builder(
                  builder: (context) {
                    // Calculate totals from credit transactions
                    double totalPaid = 0.0;
                    double totalDue = customer.creditBalance;
                    double totalCreditGiven = 0.0;

                    for (var transaction in _creditTransactions) {
                      final type = transaction['transaction_type'] as String?;
                      final amount =
                          (transaction['amount'] as num?)?.toDouble() ?? 0.0;
                      if (type == 'payment') {
                        totalPaid += amount;
                      } else if (type == 'credit') {
                        totalCreditGiven += amount;
                      }
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                'Total Due',
                                totalDue,
                                const Color(0xFFFF6B6B), // Coral/Red
                                Icons.account_balance_wallet,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSummaryCard(
                                'Total Paid',
                                totalPaid,
                                const Color(0xFF00B894), // Teal/Green
                                Icons.payment,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                'Credit Given',
                                totalCreditGiven,
                                const Color(0xFF6C5CE7), // Purple/Indigo
                                Icons.add_card,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSummaryCard(
                                'Available Credit',
                                (customer.creditLimit - customer.creditBalance)
                                    .clamp(0.0, double.infinity),
                                const Color(0xFF00B894), // Teal/Green
                                Icons.check_circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddCreditDialog(customer),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Add Credit',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C5CE7), // Purple
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showPaymentDialog(customer),
                        icon: const Icon(Icons.payment, color: Colors.white),
                        label: const Text('Receive Payment',
                            style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B894), // Teal
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
        // Bills + Transactions (scrollable)
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadCustomerOrders(_selectedCustomerId!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final orders = snapshot.data ?? [];
              final bills = orders
                  .where((o) => (o['credit_amount'] as num? ?? 0) > 0)
                  .toList()
                ..sort((a, b) {
                  final aAt = (a['created_at'] as num?)?.toInt() ?? 0;
                  final bAt = (b['created_at'] as num?)?.toInt() ?? 0;
                  return bAt.compareTo(aAt);
                });

              final totalPending = bills.fold<double>(
                0.0,
                (sum, o) =>
                    sum + ((o['credit_amount'] as num?)?.toDouble() ?? 0.0),
              );

              if (bills.isEmpty && _creditTransactions.isEmpty) {
                return Center(
                  child: Text('No credit transactions',
                      style: TextStyle(color: Colors.grey[600])),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (bills.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.receipt_long, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Bills (${bills.length})',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          'Total Pending: ${NumberFormat.currency(symbol: 'NPR ').format(totalPending)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...bills.map((order) {
                      final orderId = kIsWeb
                          ? (order['documentId'] ?? order['id'])
                          : order['id'];
                      final orderNumber =
                          (order['order_number'] as String?) ?? 'N/A';
                      final createdAt =
                          (order['created_at'] as num?)?.toInt() ?? 0;
                      final date = createdAt > 0
                          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                          : null;
                      final creditAmount =
                          (order['credit_amount'] as num? ?? 0).toDouble();
                      final paidAmount =
                          (order['paid_amount'] as num? ?? 0).toDouble();
                      final totalAmount =
                          (order['total_amount'] as num? ?? 0).toDouble();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.logoPrimary.withOpacity(0.12),
                            child: Icon(Icons.receipt_long,
                                color: AppTheme.logoPrimary),
                          ),
                          title: Text(orderNumber,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            [
                              if (date != null)
                                DateFormat('MMM dd, yyyy').format(date),
                              'Total: ${NumberFormat.currency(symbol: 'NPR ').format(totalAmount)}',
                              if (paidAmount > 0)
                                'Paid: ${NumberFormat.currency(symbol: 'NPR ').format(paidAmount)}',
                            ].join(' • '),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                NumberFormat.currency(symbol: 'NPR ')
                                    .format(creditAmount),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: creditAmount > 0
                                      ? AppTheme.warningColor
                                      : Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pending',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          onTap: orderId == null
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderDetailScreen(
                                        orderId: orderId,
                                        orderNumber: orderNumber,
                                      ),
                                    ),
                                  );
                                },
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    const Divider(),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: const [
                      Icon(Icons.swap_horiz, size: 18),
                      SizedBox(width: 8),
                      Text('Transactions',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_creditTransactions.isEmpty)
                    Text('No credit transactions',
                        style: TextStyle(color: Colors.grey[600]))
                  else
                    ..._creditTransactions.map((transaction) {
                      final createdAtRaw = transaction['created_at'];
                      final createdAt = createdAtRaw is int
                          ? createdAtRaw
                          : createdAtRaw is num
                              ? createdAtRaw.toInt()
                              : createdAtRaw is String
                                  ? (int.tryParse(createdAtRaw) ?? 0)
                                  : 0;
                      final date =
                          DateTime.fromMillisecondsSinceEpoch(createdAt);
                      final isCredit =
                          transaction['transaction_type'] == 'credit';
                      final isPayment =
                          transaction['transaction_type'] == 'payment';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCredit
                                ? AppTheme.warningColor
                                : AppTheme.successColor,
                            child: Icon(isCredit ? Icons.add : Icons.remove,
                                color: Colors.white),
                          ),
                          title: Text(
                            isCredit
                                ? 'Credit Added'
                                : isPayment
                                    ? 'Payment Received'
                                    : 'Adjustment',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(DateFormat('MMM dd, yyyy HH:mm')
                                  .format(date)),
                              if (transaction['order_id'] != null)
                                Text(
                                  'Order: ${transaction['order_id']}',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[600]),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isCredit ? '+' : '-'}${NumberFormat.currency(symbol: 'NPR ').format(transaction['amount'])}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCredit
                                      ? AppTheme.warningColor
                                      : AppTheme.successColor,
                                ),
                              ),
                              Text(
                                'Balance: ${NumberFormat.currency(symbol: 'NPR ').format(transaction['balance_after'])}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final creditLimitController = TextEditingController(text: '0');
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Customer Name *'),
                autofocus: true,
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              TextField(
                controller: creditLimitController,
                decoration:
                    const InputDecoration(labelText: 'Credit Limit (NPR)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final now = DateTime.now().millisecondsSinceEpoch;
        await dbProvider.insert('customers', {
          'name': nameController.text.trim(),
          'phone': phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          'email': emailController.text.trim().isEmpty
              ? null
              : emailController.text.trim(),
          'address': addressController.text.trim().isEmpty
              ? null
              : addressController.text.trim(),
          'credit_limit': double.parse(creditLimitController.text.isEmpty
              ? '0'
              : creditLimitController.text),
          'credit_balance': 0,
          'notes': notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          'created_at': now,
          'updated_at': now,
        });
        await _loadCustomers(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Customer added successfully'),
              backgroundColor: const Color(0xFF00B894),
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

  Future<void> _showEditCustomerDialog(Customer customer) async {
    final nameController = TextEditingController(text: customer.name);
    final phoneController = TextEditingController(text: customer.phone ?? '');
    final emailController = TextEditingController(text: customer.email ?? '');
    final addressController =
        TextEditingController(text: customer.address ?? '');
    final creditLimitController =
        TextEditingController(text: customer.creditLimit.toString());
    final notesController = TextEditingController(text: customer.notes ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Customer Name *'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
              TextField(
                controller: creditLimitController,
                decoration:
                    const InputDecoration(labelText: 'Credit Limit (NPR)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final customerId = customer.documentId ?? customer.id;
        if (customerId == null) return;

        await dbProvider.update(
          'customers',
          values: {
            'name': nameController.text.trim(),
            'phone': phoneController.text.trim().isEmpty
                ? null
                : phoneController.text.trim(),
            'email': emailController.text.trim().isEmpty
                ? null
                : emailController.text.trim(),
            'address': addressController.text.trim().isEmpty
                ? null
                : addressController.text.trim(),
            'credit_limit': double.parse(creditLimitController.text.isEmpty
                ? '0'
                : creditLimitController.text),
            'notes': notesController.text.trim().isEmpty
                ? null
                : notesController.text.trim(),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [customerId],
        );
        await _loadCustomers(); // Await to ensure data is loaded
        if (mounted) {
          setState(() {
            // Force rebuild to show updated customer details
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Customer updated'),
                backgroundColor: Color(0xFF00B894)),
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

  Future<void> _showAddCreditDialog(Customer customer) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Credit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Customer: ${customer.name}'),
            Text(
                'Current Balance: ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditBalance)}'),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              decoration:
                  const InputDecoration(labelText: 'Credit Amount (NPR)'),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (amountController.text.isEmpty ||
                  double.tryParse(amountController.text) == null ||
                  double.parse(amountController.text) <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid amount')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Credit'),
          ),
        ],
      ),
    );

    if (result == true && amountController.text.isNotEmpty) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final customerId = customer.documentId ?? customer.id;
        if (customerId == null) return;

        final amount = double.parse(amountController.text);
        final now = DateTime.now().millisecondsSinceEpoch;
        final balanceBefore = customer.creditBalance;
        final balanceAfter = balanceBefore + amount;

        // Update customer credit balance
        await dbProvider.update(
          'customers',
          values: {
            'credit_balance': balanceAfter,
            'updated_at': now,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [customerId],
        );

        // Create credit transaction
        await dbProvider.insert('credit_transactions', {
          'customer_id': customerId,
          'transaction_type': 'credit',
          'amount': amount,
          'balance_before': balanceBefore,
          'balance_after': balanceAfter,
          'notes': notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
          'created_by': authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
          'created_at': now,
          'synced': 0,
        });

        await _loadCustomers(); // Await to ensure data is loaded
        await _loadCreditTransactions(customerId);
        if (mounted) {
          // Refresh the customer details view
          setState(() {
            // Force rebuild to show updated credit balance
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Credit added successfully'),
                backgroundColor: Color(0xFF00B894)),
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

  Widget _buildSummaryCard(
      String label, double amount, Color color, IconData icon) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              NumberFormat.currency(symbol: 'NPR ').format(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPaymentDialog(Customer customer) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final paymentMethodNotifier = ValueNotifier<String>('cash');
    final isPartialPaymentNotifier = ValueNotifier<bool>(false);

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Receive Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Customer: ${customer.name}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Outstanding Amount:'),
                      Text(
                        NumberFormat.currency(symbol: 'NPR ')
                            .format(customer.creditBalance),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFFFF6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'Payment Amount (NPR) *',
                    hintText: 'Enter amount to pay',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.currency_rupee),
                    suffixText: 'NPR',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onChanged: (value) {
                    final amount = double.tryParse(value) ?? 0;
                    setDialogState(() {
                      isPartialPaymentNotifier.value =
                          amount > 0 && amount < customer.creditBalance;
                    });
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: isPartialPaymentNotifier,
                  builder: (context, isPartial, _) {
                    if (!isPartial || amountController.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Partial payment. Remaining: ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditBalance - (double.tryParse(amountController.text) ?? 0))}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: paymentMethodNotifier,
                  builder: (context, paymentMethod, _) =>
                      DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method *',
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
                    onChanged: (value) {
                      paymentMethodNotifier.value = value ?? 'cash';
                    },
                  ),
                ),
                const SizedBox(height: 16),
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
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                if (amount > customer.creditBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Amount cannot exceed outstanding balance of ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditBalance)}')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'amount': double.tryParse(amountController.text) ?? 0,
                  'paymentMethod': paymentMethodNotifier.value,
                  'notes': notesController.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B894)),
              child: const Text('Receive Payment'),
            ),
          ],
        ),
      ),
    );

    if (result != null &&
        result['amount'] != null &&
        (result['amount'] as double) > 0) {
      final paymentMethod = result['paymentMethod'] as String? ?? 'cash';
      final notes = result['notes'] as String? ?? '';
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final customerId =
            kIsWeb ? (customer.documentId ?? customer.id) : customer.id;
        if (customerId == null) return;

        final amount = result['amount'] as double;
        final now = DateTime.now().millisecondsSinceEpoch;
        final balanceBefore = customer.creditBalance;
        final balanceAfter =
            (balanceBefore - amount).clamp(0.0, double.infinity);
        final isPartial = amount < customer.creditBalance;

        // Update customer credit balance
        await dbProvider.update(
          'customers',
          values: {
            'credit_balance': balanceAfter,
            'updated_at': now,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [customerId],
        );

        // Create payment transaction
        await dbProvider.insert('credit_transactions', {
          'customer_id': customerId,
          'transaction_type': 'payment',
          'amount': amount,
          'balance_before': balanceBefore,
          'balance_after': balanceAfter,
          'payment_method': paymentMethod, // Store payment method
          'notes':
              notes.isEmpty ? (isPartial ? 'Partial payment' : null) : notes,
          // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
          'created_by': authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
          'created_at': now,
          'synced': 0,
        });

        await _loadCustomers(); // Await to ensure data is loaded
        await _loadCreditTransactions(customerId);
        if (mounted) {
          // Refresh the customer details view
          setState(() {
            // Force rebuild to show updated credit balance
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isPartial
                    ? 'Partial payment of ${NumberFormat.currency(symbol: 'NPR ').format(amount)} received. Remaining: ${NumberFormat.currency(symbol: 'NPR ').format(balanceAfter)}'
                    : 'Payment received successfully',
              ),
              backgroundColor: const Color(0xFF00B894),
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
}
