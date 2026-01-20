import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../screens/orders/order_detail_screen.dart';
import 'package:intl/intl.dart';

class SalesScreen extends StatefulWidget {
  final bool hideAppBar;
  const SalesScreen({super.key, this.hideAppBar = false});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  int _salesLimit = 50;
  bool _canLoadMore = false;

  bool _isPaidOrPartial(dynamic paymentStatus) {
    final s = (paymentStatus ?? '').toString();
    return s == 'paid' || s == 'partial';
  }

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSales());
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final startOfDay =
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day)
              .millisecondsSinceEpoch;
      final endOfDay = startOfDay + (24 * 60 * 60 * 1000) - 1;

      // PERF: Single query + in-memory filter (also avoids Firestore IN limitations).
      final rows = await dbProvider.query(
        'orders',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [startOfDay, endOfDay],
        orderBy: 'created_at DESC',
        limit: _salesLimit,
      );
      _sales = rows.where((o) => _isPaidOrPartial(o['payment_status'])).toList();
      _canLoadMore = rows.length >= _salesLimit;

      // PERF: Batch load all order_items for these orders (avoids N+1 queries).
      final orderIds =
          _sales.map((s) => s['id']).where((id) => id != null).toList();
      if (orderIds.isNotEmpty) {
        final placeholders = List.filled(orderIds.length, '?').join(',');
        final allItems = await dbProvider.query(
          'order_items',
          where: 'order_id IN ($placeholders)',
          whereArgs: orderIds,
        );

        // Group items by order_id
        final itemsByOrderId = <dynamic, List<Map<String, dynamic>>>{};
        for (final item in allItems) {
          final oid = item['order_id'];
          (itemsByOrderId[oid] ??= []).add(item);
        }

        // Attach items to each sale
        for (final sale in _sales) {
          final oid = sale['id'];
          sale['items'] = itemsByOrderId[oid] ?? <Map<String, dynamic>>[];
        }

        // PERF: Batch load all products used by these order items.
        final productIds = allItems
            .map((i) => i['product_id'])
            .where((id) => id != null)
            .toSet()
            .toList();
        if (productIds.isNotEmpty) {
          final pPlaceholders = List.filled(productIds.length, '?').join(',');
          final products = await dbProvider.query(
            'products',
            where: 'id IN ($pPlaceholders)',
            whereArgs: productIds.map((e) => e.toString()).toList(),
          );
          final productMap = {for (final p in products) p['id']: p};

          // Attach product map to each sale for quick lookup in UI.
          for (final sale in _sales) {
            sale['products'] = productMap;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading sales: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  double get _totalSales {
    return _sales.fold(
        0.0, (sum, sale) => sum + (sale['total_amount'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Sales History'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() {
                        _selectedDate = date;
                        _salesLimit = 50;
                        _canLoadMore = false;
                      });
                      _loadSales();
                    }
                  },
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              'Total Sales',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              NumberFormat.currency(symbol: 'NPR ')
                                  .format(_totalSales),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              'Orders',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              '${_sales.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Sales List
                Expanded(
                  child: _sales.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No sales found for this date',
                                  style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadSales,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _sales.length + (_canLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_canLoadMore && index == _sales.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                      top: 8, bottom: 24),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setState(() {
                                        _salesLimit += 50;
                                      });
                                      _loadSales();
                                    },
                                    child: const Text('Load more'),
                                  ),
                                );
                              }
                              final sale = _sales[index];
                              return _buildSaleCard(sale);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Color _getPaymentMethodColor(String? paymentMethod) {
    if (paymentMethod == 'cash') {
      return Colors.green; // Cash = Green
    } else if (paymentMethod == 'digital') {
      return Colors.blue; // QR/UPI/Digital = Blue
    } else if (paymentMethod == 'credit') {
      return Colors.orange; // Credit = Orange
    }
    return Colors.grey;
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final createdAtRaw = sale['created_at'];
    final createdAt = createdAtRaw is int
        ? createdAtRaw
        : createdAtRaw is num
            ? createdAtRaw.toInt()
            : createdAtRaw is String
                ? (int.tryParse(createdAtRaw) ?? 0)
                : 0;
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final orderType = sale['order_type'] as String? ?? 'dine_in';
    final paymentMethod = sale['payment_method'] as String? ?? 'cash';
    final paymentColor = _getPaymentMethodColor(paymentMethod);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: paymentColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderDetailScreen(
                // Firestore uses String doc IDs; SQLite uses int IDs
                orderId: sale['id'],
                orderNumber: sale['order_number'] as String,
              ),
            ),
          ).then((_) => _loadSales());
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
                          sale['order_number'] as String? ?? 'N/A',
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
                            const SizedBox(width: 12),
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM dd, HH:mm').format(date),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: paymentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: paymentColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          paymentMethod == 'cash' ? Icons.money : Icons.qr_code,
                          size: 14,
                          color: paymentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          paymentMethod == 'cash' ? 'Cash' : 'QR/UPI',
                          style: TextStyle(
                            color: paymentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
                        'Payment Method',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            paymentMethod == 'cash'
                                ? Icons.money
                                : Icons.qr_code,
                            size: 16,
                            color: paymentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            paymentMethod == 'cash' ? 'Cash' : 'UPI/Digital',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: paymentColor,
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
                            .format(sale['total_amount'] ?? 0),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Order Items
              if (sale['items'] != null &&
                  (sale['items'] as List).isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Items (${(sale['items'] as List).length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                ...((sale['items'] as List).take(3).map((item) {
                  final productId = item['product_id'];
                  final product = (sale['products'] as Map?)?[productId]
                      as Map<String, dynamic>?;
                  final productName =
                      product?['name'] as String? ?? 'Product $productId';
                  final quantity = item['quantity'] as num? ?? 0;
                  final unitPrice = item['unit_price'] as num? ?? 0;
                  final imageUrl = product?['image_url'] as String?;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        // Product Image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? SizedBox(
                                  width: 40,
                                  height: 40,
                                  // Web-safe: avoid `dart:io`/Image.file. Treat any string as a URL.
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 40,
                                        height: 40,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.image,
                                            size: 20, color: Colors.grey),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.image,
                                      size: 20, color: Colors.grey),
                                ),
                        ),
                        const SizedBox(width: 12),
                        // Product Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$quantity × ${NumberFormat.currency(symbol: 'NPR ').format(unitPrice)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Total Price
                        Text(
                          NumberFormat.currency(symbol: 'NPR ')
                              .format(item['total_price']),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList()),
                if ((sale['items'] as List).length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ ${(sale['items'] as List).length - 3} more items',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
