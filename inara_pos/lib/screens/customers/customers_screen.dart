import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../models/customer.dart';
import '../../utils/theme.dart';
import '../../utils/performance.dart';
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
  bool _isLoading = false;
  dynamic _selectedCustomerId;
  String _viewMode = 'list'; // 'list' or 'credits'
  int _customersLimit = 200;
  bool _canLoadMoreCustomers = false;
  String _customerSearch = '';

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomers());
  }

  Future<void> _loadCustomers() async {
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

  List<Customer> get _filteredCustomers {
    final q = _customerSearch.trim().toLowerCase();
    final list = q.isEmpty
        ? List<Customer>.from(_customers)
        : _customers
            .where((c) {
              final name = (c.name).toLowerCase();
              final phone = (c.phone ?? '').toLowerCase();
              final email = (c.email ?? '').toLowerCase();
              return name.contains(q) || phone.contains(q) || email.contains(q);
            })
            .toList();
    list.sort((a, b) => b.creditBalance.compareTo(a.creditBalance));
    return list;
  }

  bool _isAtCreditLimit(Customer c) =>
      c.creditLimit > 0 && c.creditBalance >= c.creditLimit;

  int get _atLimitCount =>
      _customers.where((c) => _isAtCreditLimit(c)).length;

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
              heroTag: 'customers_fab',
              onPressed: () => _showAddCustomerDialog(),
              backgroundColor: AppTheme.logoPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Add Customer'),
            )
          : null,
    );
  }

  static const Color _limitWarningRed = Color(0xFFFFEBEE);

  Widget _buildCustomersList() {
    final atLimit = _atLimitCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (atLimit > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: _limitWarningRed,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.red[700], size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$atLimit customer${atLimit == 1 ? '' : 's'} reached credit limit',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search customers by name, phone or email...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              suffixIcon: _customerSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _customerSearch = '');
                      },
                    )
                  : null,
            ),
            onChanged: (value) => setState(() => _customerSearch = value),
          ),
        ),
        Expanded(
          child: _customers.isEmpty
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
              : _filteredCustomers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('No customers match your search',
                              style: TextStyle(color: Colors.grey[600])),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _customerSearch = ''),
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear search'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: platformScrollPhysics,
                      cacheExtent: 400,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                      itemCount: _filteredCustomers.length +
                          (_canLoadMoreCustomers && _customerSearch.isEmpty
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (_canLoadMoreCustomers &&
                            _customerSearch.isEmpty &&
                            index == _filteredCustomers.length) {
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
                        final customer = _filteredCustomers[index];
                        final hasCredit = customer.creditBalance > 0;
                        final atLimit = _isAtCreditLimit(customer);
                        final brand = AppTheme.logoPrimary;

                        return RepaintBoundary(
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: atLimit ? _limitWarningRed : Colors.white,
                            elevation: 1,
                            child: InkWell(
                              onTap: () {
                                final customerId =
                                    customer.documentId ?? customer.id;
                                if (customerId != null) {
                                  setState(() {
                                    _selectedCustomerId = customerId;
                                    _viewMode = 'credits';
                                  });
                                  _loadCreditTransactions(customerId);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: brand,
                                      child: Text(
                                        customer.name.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            customer.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                              color: Color(0xFF1A1A1A),
                                            ),
                                          ),
                                          if (customer.phone != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Phone: ${customer.phone}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            'Balance: ${NumberFormat.currency(symbol: 'NPR ', decimalDigits: 0).format(customer.creditBalance)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: hasCredit
                                                  ? Colors.grey[900]
                                                  : Colors.grey[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          NumberFormat.currency(
                                              symbol: 'NPR ',
                                              decimalDigits: 0)
                                              .format(customer.creditBalance),
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: hasCredit
                                                ? Colors.grey[900]
                                                : Colors.grey[700],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                        if (atLimit)
                                          Chip(
                                            label: Text(
                                              'At limit',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red[700],
                                              ),
                                            ),
                                            side: BorderSide(
                                                color: Colors.red.withOpacity(0.5)),
                                            backgroundColor: _limitWarningRed,
                                          )
                                        else if (hasCredit)
                                          Chip(
                                            label: Text(
                                              'Credit',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: brand,
                                              ),
                                            ),
                                            side: BorderSide(
                                                color: brand.withOpacity(0.35)),
                                            backgroundColor: Colors.white,
                                          ),
                                        IconButton(
                                          icon: Icon(Icons.edit,
                                              color: Colors.grey[800], size: 22),
                                          onPressed: () =>
                                              _showEditCustomerDialog(customer),
                                          tooltip: 'Edit',
                                        ),
                                        IconButton(
                                          icon: Icon(
                                              Icons.account_balance_wallet,
                                              color: Colors.grey[800],
                                              size: 22),
                                          onPressed: () {
                                            final customerId =
                                                customer.documentId ?? customer.id;
                                            setState(() {
                                              _selectedCustomerId = customerId;
                                              _viewMode = 'credits';
                                            });
                                            if (customerId != null) {
                                              _loadCreditTransactions(customerId);
                                            }
                                          },
                                          tooltip: 'Credits',
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete,
                                              color: AppTheme.errorColor,
                                              size: 22),
                                          onPressed: () =>
                                              _showDeleteCustomerDialog(customer),
                                          tooltip: 'Delete',
                                        ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
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
          color: Colors.white,
          elevation: 1,
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
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.delete, color: AppTheme.errorColor),
                          onPressed: () => _showDeleteCustomerDialog(customer),
                          tooltip: 'Delete customer',
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.grey[700]),
                          onPressed: () {
                            setState(() {
                              _selectedCustomerId = null;
                              _viewMode = 'list';
                            });
                          },
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ],
                ),
                if (customer.phone != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Phone: ${customer.phone}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ),
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
                                AppTheme.errorColor,
                                Icons.account_balance_wallet,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSummaryCard(
                                'Total Paid',
                                totalPaid,
                                AppTheme.successColor,
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
                                AppTheme.logoPrimary,
                                Icons.add_card,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSummaryCard(
                                'Available Credit',
                                (customer.creditLimit - customer.creditBalance)
                                    .clamp(0.0, double.infinity),
                                AppTheme.successColor,
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
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.logoPrimary,
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
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.logoSecondary,
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

              return CustomScrollView(
                physics: platformScrollPhysics,
                cacheExtent: 200,
                slivers: [
                  if (bills.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 18, color: Colors.grey[800]),
                                const SizedBox(width: 8),
                                Text(
                                  'Bills (${bills.length})',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800]),
                                ),
                                const Spacer(),
                                Text(
                                  'Total Pending: ${NumberFormat.currency(symbol: 'NPR ').format(totalPending)}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey[800]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  if (bills.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final order = bills[index];
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
                                (order['credit_amount'] as num? ?? 0)
                                    .toDouble();
                            final paidAmount =
                                (order['paid_amount'] as num? ?? 0).toDouble();
                            final totalAmount =
                                (order['total_amount'] as num? ?? 0)
                                    .toDouble();

                            return RepaintBoundary(
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: Colors.white,
                                elevation: 1,
                                child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.logoPrimary.withOpacity(0.12),
                            child: Icon(Icons.receipt_long,
                                color: AppTheme.logoPrimary),
                          ),
                          title: Text(orderNumber,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A))),
                          subtitle: Text(
                            [
                              if (date != null)
                                DateFormat('MMM dd, yyyy').format(date),
                              'Total: ${NumberFormat.currency(symbol: 'NPR ').format(totalAmount)}',
                              if (paidAmount > 0)
                                'Paid: ${NumberFormat.currency(symbol: 'NPR ').format(paidAmount)}',
                            ].join(' • '),
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
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
                                  fontSize: 14,
                                  color: creditAmount > 0
                                      ? Colors.grey[900]
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
                                    smoothPageRoute(
                                      builder: (_) => OrderDetailScreen(
                                        orderId: orderId,
                                        orderNumber: orderNumber,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                          },
                          childCount: bills.length,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.swap_horiz,
                                  size: 18, color: Colors.grey[800]),
                              const SizedBox(width: 8),
                              Text(
                                'Transactions',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                  if (_creditTransactions.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text('No credit transactions',
                            style: TextStyle(color: Colors.grey[600])),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final transaction =
                                _creditTransactions[index];
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

                            return RepaintBoundary(
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: Colors.white,
                                elevation: 1,
                                child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCredit
                                ? AppTheme.logoPrimary
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
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A)),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('MMM dd, yyyy HH:mm').format(date),
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[600]),
                              ),
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
                                  fontSize: 14,
                                  color: isCredit
                                      ? AppTheme.logoSecondary
                                      : AppTheme.successColor,
                                ),
                              ),
                              Text(
                                'Balance: ${NumberFormat.currency(symbol: 'NPR ').format(transaction['balance_after'])}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      ),
                            );
                          },
                          childCount: _creditTransactions.length,
                        ),
                      ),
                    ),
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
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'Enter customer name',
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'Enter customer name',
                ),
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

    if (result == true) {
      if (nameController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter customer name'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
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

  Future<void> _showDeleteCustomerDialog(Customer customer) async {
    String message =
        'Delete "${customer.name}"? This will remove their credit history. Orders linked to this customer will be unlinked. This cannot be undone.';
    if (customer.creditBalance > 0) {
      message += '\n\nWarning: This customer has ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditBalance)} outstanding credit.';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final customerId = customer.documentId ?? customer.id;
      if (customerId == null) return;

      // Delete credit transactions for this customer
      await dbProvider.delete(
        'credit_transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Unlink orders from this customer
      await dbProvider.update(
        'orders',
        values: {'customer_id': null, 'customer_name': null},
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );

      // Delete the customer
      await dbProvider.delete(
        'customers',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [customerId],
      );

      if (_selectedCustomerId == customerId) {
        setState(() {
          _selectedCustomerId = null;
          _viewMode = 'list';
          _creditTransactions = [];
        });
      }
      await _loadCustomers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${customer.name} deleted'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _showAddCreditDialog(Customer customer) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final amount = double.tryParse(amountController.text) ?? 0;
          final balanceAfter = customer.creditBalance + amount;
          final wouldExceedLimit = customer.creditLimit > 0 &&
              balanceAfter > customer.creditLimit;

          return AlertDialog(
            title: const Text('Add Credit'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Customer: ${customer.name}'),
                Text(
                    'Current Balance: ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditBalance)}'),
                if (customer.creditLimit > 0)
                  Text(
                      'Credit Limit: ${NumberFormat.currency(symbol: 'NPR ').format(customer.creditLimit)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration:
                      const InputDecoration(labelText: 'Credit Amount (NPR)'),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                ),
                if (wouldExceedLimit) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.red[700], size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This would exceed credit limit by ${NumberFormat.currency(symbol: 'NPR ').format(balanceAfter - customer.creditLimit)}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.red[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
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
          );
        },
      ),
    );

    if (result == true && amountController.text.isNotEmpty) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final authProvider =
            Provider.of<InaraAuthProvider>(context, listen: false);
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
                backgroundColor: AppTheme.successColor),
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
      color: Colors.white,
      elevation: 1,
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
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              NumberFormat.currency(symbol: 'NPR ').format(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
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
        final authProvider =
            Provider.of<InaraAuthProvider>(context, listen: false);
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
