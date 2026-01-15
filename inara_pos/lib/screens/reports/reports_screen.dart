import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../customers/customers_screen.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class ReportsScreen extends StatefulWidget {
  final bool hideAppBar;
  const ReportsScreen({super.key, this.hideAppBar = false});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  Map<String, dynamic> _reportData = {};
  List<Map<String, dynamic>> _dailySales = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final start = DateTime(_startDate.year, _startDate.month, _startDate.day)
          .millisecondsSinceEpoch;
      final end = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59)
          .millisecondsSinceEpoch;

      // Total Sales (include paid and partial payments)
      final orders = await dbProvider.query(
        'orders',
        where: 'created_at >= ? AND created_at <= ? AND payment_status IN (?, ?)',
        whereArgs: [start, end, 'paid', 'partial'],
      );

      final totalSales = orders.fold<double>(
        0.0,
        (sum, o) => sum + ((o['total_amount'] as num?)?.toDouble() ?? 0.0),
      );
      final totalOrders = orders.length;

      // Total Expenses (in-house) for the same date range
      final expenses = await dbProvider.query(
        'expenses',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [start, end],
      );
      final totalExpenses = expenses.fold<double>(
        0.0,
        (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0.0),
      );
      final netProfit = totalSales - totalExpenses;
      
      // Credit Given (from orders with credit_amount > 0 in date range)
      final allOrdersInRange = await dbProvider.query(
        'orders',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [start, end],
      );
      final creditGiven = allOrdersInRange.fold(0.0, (sum, o) => sum + (o['credit_amount'] as num? ?? 0).toDouble());
      
      // Credit Collected (from credit transactions of type 'payment')
      final creditTransactions = await dbProvider.query(
        'credit_transactions',
        where: 'created_at >= ? AND created_at <= ? AND transaction_type = ?',
        whereArgs: [start, end, 'payment'],
      );
      final creditCollected = creditTransactions.fold(0.0, (sum, t) => sum + (t['amount'] as num? ?? 0).toDouble());
      
      // Today's Credit (total customer credit balances)
      final customers = await dbProvider.query('customers');
      final todaysCredit = customers.fold(0.0, (sum, c) => sum + (c['credit_balance'] as num? ?? 0).toDouble());
      
      // Credit Sales (orders paid with credit or partial credit)
      final creditSales = allOrdersInRange.where((o) {
        final paymentMethod = o['payment_method'] as String?;
        final creditAmount = (o['credit_amount'] as num? ?? 0).toDouble();
        return paymentMethod == 'credit' || creditAmount > 0;
      }).fold(0.0, (sum, o) => sum + (o['total_amount'] as num).toDouble());
      
      // Regular Sales (cash, digital, card - excluding credit)
      final regularSales = orders.where((o) {
        final paymentMethod = o['payment_method'] as String?;
        return paymentMethod != 'credit';
      }).fold(0.0, (sum, o) => sum + (o['total_amount'] as num).toDouble());

      // Payment methods breakdown
      final cash = orders.where((o) => o['payment_method'] == 'cash').fold(
          0.0, (sum, o) => sum + (o['total_amount'] as num).toDouble());
      final card = orders.where((o) => o['payment_method'] == 'card').fold(
          0.0, (sum, o) => sum + (o['total_amount'] as num).toDouble());
      final digital = orders.where((o) => o['payment_method'] == 'digital').fold(
          0.0, (sum, o) => sum + (o['total_amount'] as num).toDouble());

      // Daily sales breakdown - group by date and time
      final dailyList = <Map<String, dynamic>>[];
      for (final order in orders) {
        final createdAtRaw = order['created_at'];
        final createdAt = createdAtRaw is int
            ? createdAtRaw
            : createdAtRaw is num
                ? createdAtRaw.toInt()
                : createdAtRaw is String
                    ? (int.tryParse(createdAtRaw) ?? 0)
                    : 0;
        final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
        dailyList.add({
          'datetime': date,
          'amount': (order['total_amount'] as num).toDouble(),
        });
      }
      
      // Group by date and sum amounts, keep time info
      final dailyMap = <String, Map<String, dynamic>>{};
      for (final item in dailyList) {
        final dateTime = item['datetime'] as DateTime;
        // Use date as key (YYYY-MM-DD format for proper sorting)
        final dateKey = DateFormat('yyyy-MM-dd').format(dateTime);
        
        if (!dailyMap.containsKey(dateKey)) {
          dailyMap[dateKey] = {
            'datetime': dateTime,
            'dayName': DateFormat('EEE').format(dateTime), // Day name (Sun, Mon, etc.)
            'date': DateFormat('MMM dd').format(dateTime), // Date (Jan 12)
            'fullDate': DateFormat('MMM dd, yyyy').format(dateTime), // Full date (Jan 12, 2026)
            'firstOrderTime': dateTime,
            'lastOrderTime': dateTime,
            'amount': 0.0,
          };
        }
        dailyMap[dateKey]!['amount'] = (dailyMap[dateKey]!['amount'] as double) + (item['amount'] as double);
        // Track first and last order times
        if (dateTime.isBefore(dailyMap[dateKey]!['firstOrderTime'] as DateTime)) {
          dailyMap[dateKey]!['firstOrderTime'] = dateTime;
        }
        if (dateTime.isAfter(dailyMap[dateKey]!['lastOrderTime'] as DateTime)) {
          dailyMap[dateKey]!['lastOrderTime'] = dateTime;
        }
      }
      
      _dailySales = dailyMap.values.toList()
        ..sort((a, b) => (a['datetime'] as DateTime).compareTo(b['datetime'] as DateTime));
      
      // If no sales data, create empty entries for each day in the range to show the chart
      if (_dailySales.isEmpty) {
        final days = _endDate.difference(_startDate).inDays + 1;
        _dailySales = List.generate(days, (index) {
          final date = _startDate.add(Duration(days: index));
          return {
            'datetime': date,
            'dayName': DateFormat('EEE').format(date),
            'date': DateFormat('MMM dd').format(date),
            'fullDate': DateFormat('MMM dd, yyyy').format(date),
            'firstOrderTime': date,
            'lastOrderTime': date,
            'amount': 0.0,
          };
        });
      }

      // Item-wise sales
      // NOTE: Firestore query wrapper doesn't support IN (...) yet, so skip item aggregation on web for stability/perf.
      final Map<dynamic, double> itemSales = {};
      if (!kIsWeb) {
        final orderIds = orders.map((o) => o['id']).whereType<int>().toList();
        final items = orderIds.isEmpty
            ? <Map<String, dynamic>>[]
            : await dbProvider.query(
                'order_items',
                where: 'order_id IN (${List.filled(orderIds.length, '?').join(',')})',
                whereArgs: orderIds,
              );

        for (final item in items) {
          final productId = item['product_id'];
          final amount = (item['total_price'] as num?)?.toDouble() ?? 0.0;
          itemSales[productId] = (itemSales[productId] ?? 0.0) + amount;
        }
      }

      if (!mounted) return;
      setState(() {
        _reportData = {
          'totalSales': totalSales,
          'totalOrders': totalOrders,
          'todaysCredit': todaysCredit,
          'creditGiven': creditGiven,
          'creditCollected': creditCollected,
          'creditSales': creditSales,
          'regularSales': regularSales,
          'totalExpenses': totalExpenses,
          'netProfit': netProfit,
          'cash': cash,
          'card': card,
          'digital': digital,
          'itemSales': itemSales,
        };
      });
    } catch (e) {
      debugPrint('Error loading report: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar ? null : AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadReport();
            },
            tooltip: 'Refresh Reports',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Range Selector - Compact
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Flexible(
                            child: InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate,
                                  firstDate: DateTime(2020),
                                  lastDate: _endDate,
                                );
                                if (date != null) {
                                  setState(() => _startDate = date);
                                  _loadReport();
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'From: ${DateFormat('MMM dd, yyyy').format(_startDate)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _endDate,
                                  firstDate: _startDate,
                                  lastDate: DateTime.now(),
                                );
                                if (date != null) {
                                  setState(() => _endDate = date);
                                  _loadReport();
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'To: ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Total Sales and Today's Credit Section (with gradients)
                  Row(
                    children: [
                      Expanded(
                        child: _buildGradientCard(
                          title: 'Total Sales',
                          value: NumberFormat.currency(symbol: 'NPR ').format(_reportData['totalSales'] ?? 0),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFF9C4), // Very light yellow
                              Color(0xFFFFF59D), // Light yellow
                            ],
                          ),
                          icon: Icons.point_of_sale,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CustomersScreen()),
                            );
                          },
                          child: _buildGradientCard(
                            title: 'Today\'s Credit',
                            value: NumberFormat.currency(symbol: 'NPR ').format(_reportData['todaysCredit'] ?? 0),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFFF8E1), // Very light cream
                                Color(0xFFFFECB3), // Light cream
                              ],
                            ),
                            icon: Icons.credit_card,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Credit Given and Total Orders (on same line)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CustomersScreen()),
                            );
                          },
                          child: _buildGradientCard(
                            title: 'Credit Given',
                            value: NumberFormat.currency(symbol: 'NPR ').format(_reportData['creditGiven'] ?? 0),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFFE0B2), // Very light orange
                                Color(0xFFFFCC80), // Light orange
                              ],
                            ),
                            icon: Icons.people,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildGradientCard(
                          title: 'Total Orders',
                          value: '${_reportData['totalOrders'] ?? 0}',
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFC8E6C9), // Very light green
                              Color(0xFFA5D6A7), // Light green
                            ],
                          ),
                          icon: Icons.shopping_cart,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Expenses and Net (Sales - Expenses)
                  Row(
                    children: [
                      Expanded(
                        child: _buildGradientCard(
                          title: 'Total Expenses',
                          value: NumberFormat.currency(symbol: 'NPR ').format(_reportData['totalExpenses'] ?? 0),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFEBEE), // Very light red
                              Color(0xFFFFCDD2), // Light red
                            ],
                          ),
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildGradientCard(
                          title: 'Net',
                          value: NumberFormat.currency(symbol: 'NPR ').format(_reportData['netProfit'] ?? 0),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFE3F2FD), // Very light blue
                              Color(0xFFBBDEFB), // Light blue
                            ],
                          ),
                          icon: Icons.account_balance_wallet,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sales (Credit and Sales) Pie Chart
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sales (Credit and Sales)', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 200,
                            child: _buildSalesPieChart(),
                          ),
                          const SizedBox(height: 16),
                          _buildPaymentRow('Regular Sales', _reportData['regularSales'] ?? 0, Colors.green),
                          _buildPaymentRow('Credit Sales', _reportData['creditSales'] ?? 0, Colors.orange),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Daily Sales Line Chart
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Daily Sales', style: Theme.of(context).textTheme.titleLarge),
                              TextButton(
                                onPressed: () {
                                  // Could add trend view toggle here
                                },
                                child: const Text('Trend'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Legend
                          Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Daily Revenue (NPR)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.only(left: 0.0, right: 20.0),
                            child: SizedBox(
                              height: 250,
                              child: _buildDailySalesLineChart(),
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

  Widget _buildSalesPieChart() {
    final regularSales = _reportData['regularSales'] ?? 0.0;
    final creditSales = _reportData['creditSales'] ?? 0.0;
    final total = regularSales + creditSales;

    if (total == 0) {
      return Center(
        child: Text('No sales data available', style: TextStyle(color: Colors.grey[600])),
      );
    }

    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            value: regularSales,
            title: '${((regularSales / total) * 100).toStringAsFixed(1)}%',
            color: Colors.green,
            radius: 60,
          ),
          PieChartSectionData(
            value: creditSales,
            title: '${((creditSales / total) * 100).toStringAsFixed(1)}%',
            color: Colors.orange,
            radius: 60,
          ),
        ],
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    );
  }

  Widget _buildDailySalesLineChart() {
    if (_dailySales.isEmpty) {
      return Center(
        child: Text('No sales data available', style: TextStyle(color: Colors.grey[600])),
      );
    }

    final amounts = _dailySales.map((d) => d['amount'] as double).toList();
    final maxAmount = amounts.isEmpty ? 100.0 : (amounts.reduce((a, b) => a > b ? a : b));
    final minY = 0.0;
    final maxY = maxAmount > 0 ? maxAmount * 1.2 : 100.0; // Ensure minimum range for visibility
    
    // Calculate step size for Y-axis
    final stepSize = (maxY - minY) / 5;
    
    // Prepare line chart spots
    final spots = _dailySales.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value['amount'] as double);
    }).toList();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 8,
            tooltipBgColor: Colors.grey[900]!,
            tooltipPadding: const EdgeInsets.all(12),
            tooltipMargin: 8,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final index = touchedSpot.x.toInt();
                if (index >= 0 && index < _dailySales.length) {
                  final sale = _dailySales[index];
                  final dayName = sale['dayName'] as String? ?? '';
                  final fullDate = sale['fullDate'] as String? ?? '';
                  final amount = NumberFormat.currency(symbol: 'Rs. ').format(touchedSpot.y);
                  
                  return LineTooltipItem(
                    'Day: $dayName\n'
                    'Date: $fullDate\n'
                    'Revenue: $amount',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }
                return null;
              }).toList();
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 35,
              interval: _dailySales.length > 7 ? 2.0 : 1.0, // Show every other label if too many days
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < _dailySales.length) {
                  final sale = _dailySales[index];
                  final date = sale['date'] as String? ?? ''; // Format: "MMM dd" (e.g., "Jan 7")
                  
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      date,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: stepSize,
              getTitlesWidget: (value, meta) {
                if (value < minY || value > maxY) return const Text('');
                // Round to avoid floating point issues
                final roundedValue = (value / stepSize).round() * stepSize;
                if ((value - roundedValue).abs() > 0.01) return const Text('');
                
                // Format as Rs. X.XK or shorter format
                String label;
                if (value == 0) {
                  label = '0';
                } else if (value >= 1000) {
                  label = 'Rs.${(value / 1000).toStringAsFixed(1)}K';
                } else {
                  label = 'Rs.${value.toStringAsFixed(0)}';
                }
                
                return Padding(
                  padding: const EdgeInsets.only(right: 2.0),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          drawHorizontalLine: true,
          horizontalInterval: stepSize,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey[300]!,
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey[300]!, width: 1),
            left: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.orange,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.orange,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientCard({
    required String title,
    required String value,
    required Gradient gradient,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87, // Dark/black text
                ),
              ),
              Icon(
                icon,
                size: 20,
                color: Colors.black87, // Dark/black icon
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87, // Dark/black text
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(method),
            ],
          ),
          Text(
            NumberFormat.currency(symbol: 'NPR ').format(amount),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
