import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/unified_database_provider.dart';
import '../../widgets/responsive_wrapper.dart';
import '../orders/orders_screen.dart';

class RecentActivityScreen extends StatefulWidget {
  const RecentActivityScreen({super.key});

  @override
  State<RecentActivityScreen> createState() => _RecentActivityScreenState();
}

class _RecentActivityScreenState extends State<RecentActivityScreen> {
  List<_ActivityItem> _allActivity = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllActivity();
    });
  }

  Future<void> _loadAllActivity() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      List<_ActivityItem> allActivity = [];

      // Load all orders (no limit)
      final allOrders = await dbProvider.query(
        'orders',
        orderBy: 'created_at DESC',
      );

      // Load all expenses (no limit)
      final allExpenses = await dbProvider.query(
        'expenses',
        orderBy: 'created_at DESC',
      );

      // Load all credit transactions (no limit)
      final allCredits = await dbProvider.query(
        'credit_transactions',
        orderBy: 'created_at DESC',
      );

      // Process orders
      for (final o in allOrders) {
        final createdAt = (o['created_at'] as num?)?.toInt() ?? 0;
        final orderNumber = (o['order_number'] as String?) ?? 'Order';
        final paymentStatus = (o['payment_status'] as String?) ?? 'unpaid';
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        final orderId = o['id']?.toString() ?? o['documentId']?.toString();
        allActivity.add(
          _ActivityItem(
            createdAt: createdAt,
            icon: Icons.receipt_long,
            color: Colors.blueGrey,
            title: orderNumber,
            subtitle: 'Order • ${paymentStatus.toUpperCase()}',
            amount: total,
            orderId: orderId,
          ),
        );
      }

      // Process expenses
      for (final e in allExpenses) {
        final createdAt = (e['created_at'] as num?)?.toInt() ?? 0;
        final title = (e['title'] as String?) ?? 'Expense';
        final method = (e['payment_method'] as String?)?.replaceAll('_', ' ');
        final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
        allActivity.add(
          _ActivityItem(
            createdAt: createdAt,
            icon: Icons.payments_outlined,
            color: Colors.deepOrange,
            title: title,
            subtitle: method == null || method.trim().isEmpty
                ? 'Expense'
                : 'Expense • $method',
            amount: amount,
          ),
        );
      }

      // Process credit transactions
      for (final t in allCredits) {
        final createdAt = (t['created_at'] as num?)?.toInt() ?? 0;
        final type = (t['transaction_type'] as String?) ?? 'credit';
        final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
        final isPayment = type == 'payment';
        allActivity.add(
          _ActivityItem(
            createdAt: createdAt,
            icon: isPayment ? Icons.payments : Icons.credit_card,
            color: isPayment ? Colors.green : Colors.orange,
            title: isPayment ? 'Credit payment received' : 'Credit given',
            subtitle: isPayment ? 'Credit • Payment' : 'Credit • Given',
            amount: amount,
          ),
        );
      }

      // Sort by creation date (most recent first)
      allActivity.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _allActivity = allActivity;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading all activity: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Recent Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllActivity,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allActivity.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No activity found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your transactions will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAllActivity,
                  child: kIsWeb
                      ? ResponsiveWrapper(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _allActivity.length,
                            itemBuilder: (context, index) {
                              return _buildActivityItem(_allActivity[index]);
                            },
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _allActivity.length,
                          itemBuilder: (context, index) {
                            return _buildActivityItem(_allActivity[index]);
                          },
                        ),
                ),
    );
  }

  Widget _buildActivityItem(_ActivityItem activity) {
    final currency = NumberFormat.currency(symbol: 'NPR ', decimalDigits: 0);
    final timeFmt = DateFormat('MMM dd, yyyy • hh:mm a');
    final dt = activity.createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(activity.createdAt)
        : null;

    final isOrder =
        activity.icon == Icons.receipt_long && activity.orderId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: isOrder
            ? () {
                // Navigate to orders screen
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OrdersScreen(),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: activity.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(activity.icon, color: activity.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isOrder
                            ? Theme.of(context).primaryColor
                            : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activity.subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        timeFmt.format(dt),
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(activity.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  if (isOrder) ...[
                    const SizedBox(height: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Colors.grey[400],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityItem {
  final int createdAt;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double amount;
  final String? orderId;

  const _ActivityItem({
    required this.createdAt,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.orderId,
  });
}
