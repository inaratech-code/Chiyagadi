import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../providers/unified_database_provider.dart';
import '../../services/inventory_ledger_service.dart';
import '../../widgets/responsive_wrapper.dart';
import '../../utils/theme.dart';
import '../inventory/inventory_screen.dart';
import '../customers/customers_screen.dart';
import '../settings/settings_screen.dart';
import '../reports/reports_screen.dart';
import '../purchases/purchases_screen.dart';
import '../purchases/suppliers_screen.dart';
import '../orders/orders_screen.dart';
import '../menu/menu_screen.dart';
import '../expenses/expenses_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double _todaySales = 0.0;
  double _todayCredit = 0.0;
  int _lowStockCount = 0;
  String _shopName = 'Shop';
  List<_ActivityItem> _recentActivity = const [];
  bool _isLoading = true; // Add loading state
  // FIXED: Use ledger service instead of direct inventory service
  final InventoryLedgerService _ledgerService = InventoryLedgerService();

  bool _isPaidOrPartial(dynamic paymentStatus) {
    final s = (paymentStatus ?? '').toString();
    return s == 'paid' || s == 'partial';
  }

  @override
  void initState() {
    super.initState();
    // PERF: Show UI immediately, then load data asynchronously
    // This ensures the page appears instantly on Android/iOS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Small delay to ensure UI is fully rendered
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          _loadDashboardData();
        }
      });
    });
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      // Initialize database (should be fast if already initialized)
      await dbProvider.init();

      String nextShopName = _shopName;
      double nextTodaySales = 0.0;
      double nextTodayCredit = 0.0;
      int nextLowStockCount = 0;
      List<_ActivityItem> nextRecent = [];

      // Get today's sales and credit
      final now = DateTime.now();
      final startOfDay =
          DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59)
          .millisecondsSinceEpoch;

      // PERF: Run independent queries in parallel.
      final results = await Future.wait<List<Map<String, dynamic>>>([
        // 0: settings
        dbProvider.query('settings'),
        // 1: orders in today's range (filter paid/partial in-memory on web)
        kIsWeb
            ? dbProvider.query(
                'orders',
                where: 'created_at >= ? AND created_at <= ?',
                whereArgs: [startOfDay, endOfDay],
              )
            : dbProvider.query(
                'orders',
                where:
                    'created_at >= ? AND created_at <= ? AND payment_status IN (?, ?)',
                whereArgs: [startOfDay, endOfDay, 'paid', 'partial'],
              ),
        // 2: today's credit transactions
        dbProvider.query(
          'credit_transactions',
          // Web/Firestore: (created_at range + transaction_type) often requires a composite index.
          // Fetch by date range only and filter in-memory to avoid index requirement.
          where: 'created_at >= ? AND created_at <= ?',
          whereArgs: [startOfDay, endOfDay],
        ),
        // 3: purchasable products for low stock
        kIsWeb
            ? dbProvider.query(
                'products',
                where: 'is_purchasable = ?',
                whereArgs: [1],
              )
            : dbProvider.query(
                'products',
                where: 'is_purchasable = ?',
                whereArgs: [1],
              ),
        // 4: recent orders (limit to 3 for faster loading)
        dbProvider.query('orders', orderBy: 'created_at DESC', limit: 3),
        // 5: recent expenses (limit to 3 for faster loading)
        dbProvider.query('expenses', orderBy: 'created_at DESC', limit: 3),
        // 6: recent credits (limit to 3 for faster loading)
        dbProvider.query('credit_transactions',
            orderBy: 'created_at DESC', limit: 3),
      ]);

      final settingsRows = results[0];
      final todayOrdersRaw = results[1];
      final todayCreditTransactionsRaw = results[2];
      final products = results[3];
      final recentOrders = results[4];
      final recentExpenses = results[5];
      final recentCredits = results[6];

      // Get shop name from settings
      for (final setting in settingsRows) {
        if (setting['key'] == 'cafe_name_en') {
          nextShopName = setting['value'] as String? ?? 'Shop';
          break;
        }
      }

      final todayOrders = kIsWeb
          ? todayOrdersRaw
              .where((o) => _isPaidOrPartial(o['payment_status']))
              .toList()
          : todayOrdersRaw;

      nextTodaySales = todayOrders.fold<double>(
        0.0,
        (sum, order) =>
            sum + ((order['total_amount'] as num?)?.toDouble() ?? 0.0),
      );

      final todayCreditTransactions = todayCreditTransactionsRaw
          .where((t) => (t['transaction_type'] ?? '').toString() == 'credit')
          .toList();

      nextTodayCredit = todayCreditTransactions.fold<double>(
        0.0,
        (sum, transaction) =>
            sum + ((transaction['amount'] as num?)?.toDouble() ?? 0.0),
      );

      // Load stock data asynchronously after main data is shown
      if (mounted && products.isNotEmpty) {
        final productIds = products
            .map((p) => p['id'])
            .where((id) => id != null)
            .toList()
            .cast<dynamic>();
        
        // Load stock in background to not block UI
        _ledgerService.getCurrentStockBatch(
          context: context,
          productIds: productIds,
        ).then((stockMap) {
          if (!mounted) return;
          int lowStockCount = 0;
          for (final pid in productIds) {
            final currentStock = stockMap[pid] ?? 0.0;
            if (currentStock <= 0) lowStockCount++;
          }
          if (mounted) {
            setState(() => _lowStockCount = lowStockCount);
          }
        }).catchError((e) {
          debugPrint('Error loading stock: $e');
        });
      }
      
      nextLowStockCount = 0; // Will be updated async

      for (final o in recentOrders) {
        final createdAt = (o['created_at'] as num?)?.toInt() ?? 0;
        final orderNumber = (o['order_number'] as String?) ?? 'Order';
        final paymentStatus = (o['payment_status'] as String?) ?? 'unpaid';
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        nextRecent.add(
          _ActivityItem(
            createdAt: createdAt,
            icon: Icons.receipt_long,
            color: Colors.blueGrey,
            title: orderNumber,
            subtitle: 'Order • ${paymentStatus.toUpperCase()}',
            amount: total,
          ),
        );
      }

      for (final e in recentExpenses) {
        final createdAt = (e['created_at'] as num?)?.toInt() ?? 0;
        final title = (e['title'] as String?) ?? 'Expense';
        final method = (e['payment_method'] as String?)?.replaceAll('_', ' ');
        final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
        nextRecent.add(
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

      for (final t in recentCredits) {
        final createdAt = (t['created_at'] as num?)?.toInt() ?? 0;
        final type = (t['transaction_type'] as String?) ?? 'credit';
        final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
        final isPayment = type == 'payment';
        nextRecent.add(
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

      nextRecent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (nextRecent.length > 6) nextRecent = nextRecent.take(6).toList();

      if (!mounted) return;
      setState(() {
        _shopName = nextShopName;
        _todaySales = nextTodaySales;
        _todayCredit = nextTodayCredit;
        _lowStockCount = nextLowStockCount;
        _recentActivity = nextRecent;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = width < 380 ? 14.0 : 16.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: true,
        left: true,
        right: true,
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: kIsWeb
              ? ResponsiveWrapper(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildContent(context, authProvider),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildContent(context, authProvider),
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, AuthProvider authProvider) {
    if (_isLoading) {
      return _buildLoadingContent();
    }
    
    return [
      // Welcome Section with Logo and Settings Button
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                // Logo
                Container(
                  width: kIsWeb ? 80 : 70,
                  height: kIsWeb ? 80 : 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFEB3B), // Light yellow center
                        const Color(0xFFFFC107), // Golden yellow edges
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFC107).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.jpeg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.local_cafe,
                          color: Color(0xFF8B4513), // Brown
                          size: 40,
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(width: kIsWeb ? 16 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Welcome,\nChiyagadi',
                        style: TextStyle(
                          fontSize: kIsWeb ? 26 : 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1A1A),
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Powered by ',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Inara Tech',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8B4513),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      const SizedBox(height: 24),

      // Summary Cards with Gradients
      _buildSummaryCards(),
      const SizedBox(height: 24),

      // Low Stock Alert
      if (_lowStockCount > 0) ...[
        _buildLowStockAlert(),
        const SizedBox(height: 24),
      ],

      // Quick Access Tiles
      Text(
        'Quick Access',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
      const SizedBox(height: 16),
      _buildQuickAccessTiles(context, authProvider),
      const SizedBox(height: 32),

      // Recent Activity Section
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Recent Activity',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          TextButton.icon(
            onPressed: _loadDashboardData,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('See All'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[700],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildRecentActivity(),
      const SizedBox(height: 32),
      // Powered by Inara Tech
      Center(
        child: Column(
          children: [
            Text(
              'Powered by',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Inara Tech',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8B4513),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildLoadingContent() {
    return [
      // Welcome Section Skeleton
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 200,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      // Summary Cards Skeleton
      Row(
        children: [
          Expanded(
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      // Quick Access Skeleton
      Container(
        width: 120,
        height: 20,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(height: 16),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      const SizedBox(height: 32),
      // Recent Activity Skeleton
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 140,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            width: 80,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ...List.generate(3, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )),
    ];
  }

  Widget _buildSummaryCards() {
    final currencyFormat =
        NumberFormat.currency(symbol: 'NPR ', decimalDigits: 0);

    return Column(
      children: [
        // First Row: Total Sales and Today's Credit (reversed)
        Row(
          children: [
            Expanded(
              child: _buildGradientCard(
                title: 'Total Sales',
                value: currencyFormat.format(_todaySales),
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
                  // Navigate to Customers screen when credit card is tapped
                  if (widget.onNavigate != null) {
                    widget.onNavigate!(7); // Customers screen index
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CustomersScreen()),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: _buildGradientCard(
                  title: 'Today\'s Credit',
                  value: currencyFormat.format(_todayCredit),
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
      ],
    );
  }

  Widget _buildGradientCard({
    required String title,
    required String value,
    required Gradient gradient,
    required IconData icon,
  }) {
    final isMobile = !kIsWeb;
    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 20),
      height: isMobile ? 140 : 120, // Make boxes bigger on mobile
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
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: kIsWeb ? 14 : 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87, // Dark/black text
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                size: kIsWeb ? 20 : 22,
                color: Colors.black87, // Dark/black icon
              ),
            ],
          ),
          SizedBox(height: kIsWeb ? 12 : 16),
          Text(
            value,
            style: TextStyle(
              fontSize: kIsWeb ? 24 : 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87, // Dark/black text
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.red[50],
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.red[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_lowStockCount item(s) are low on stock!',
              style: TextStyle(
                color: Colors.red[900],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              if (widget.onNavigate != null) {
                widget.onNavigate!(6); // Inventory screen index
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryScreen()),
                );
              }
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessTiles(
      BuildContext context, AuthProvider authProvider) {
    // Reordered by daily usage: Orders, Menu, Inventory, Customers, Reports, Purchases
    // Map labels to navigation indices in HomeScreen
    final Map<String, int> navigationMap = {
      'Orders': 1,
      'Menu': 3,
      'Inventory': 6, // Added to bottom navigation
      'Customers': 7, // Added to bottom navigation
      'Reports': 5,
      'Purchases': 8, // Added to bottom navigation (admin only)
      'Expenses': 9,
    };

    // Helper function to navigate - uses callback if available and screen is in nav, otherwise Navigator.push
    void navigateToScreen(String label, Widget screen) {
      final navIndex = navigationMap[label];
      if (widget.onNavigate != null && navIndex != null && navIndex >= 0) {
        widget.onNavigate!(navIndex);
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        );
      }
    }

    final tiles = [
      {
        'icon': Icons.receipt_long,
        'label': 'Orders',
        'color': const Color(0xFF6366F1),
        'onTap': () => navigateToScreen('Orders', const OrdersScreen()),
      },
      {
        'icon': Icons.restaurant_menu,
        'label': 'Menu',
        // Use brand gold for Menu section
        'color': AppTheme.logoPrimary,
        'onTap': () => navigateToScreen('Menu', const MenuScreen()),
      },
      {
        'icon': Icons.inventory_2,
        'label': 'Inventory',
        'color': const Color(0xFFF59E0B),
        'onTap': () => navigateToScreen('Inventory', const InventoryScreen()),
      },
      {
        'icon': Icons.people,
        'label': 'Customers',
        'color': const Color(0xFF8B5CF6),
        'onTap': () => navigateToScreen('Customers', const CustomersScreen()),
      },
      {
        'icon': Icons.analytics,
        'label': 'Reports',
        'color': const Color(0xFFEF4444),
        'onTap': () => navigateToScreen('Reports', const ReportsScreen()),
      },
      {
        'icon': Icons.shopping_bag,
        'label': 'Purchases',
        'color': const Color(0xFF06B6D4),
        'onTap': () => navigateToScreen('Purchases', const PurchasesScreen()),
      },
      {
        'icon': Icons.business,
        'label': 'Suppliers',
        'color': AppTheme.logoPrimary, // Golden yellow from logo
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SuppliersScreen()),
            ),
      },
      {
        'icon': Icons.payments,
        'label': 'Expenses',
        'color': AppTheme.logoSecondary,
        'onTap': () => navigateToScreen('Expenses', const ExpensesScreen()),
      },
    ];

    final width = MediaQuery.of(context).size.width;
    // Treat web-on-phone like mobile so tiles don't overlap.
    final isCompact = width < 700;

    // Responsive grid: mobile (Android/iOS) = 3 columns, tablets = 3, desktop = 4
    final crossAxisCount = kIsWeb
        ? (width > 1200 ? 4 : 3) // Web: 4 columns on large screens, 3 on smaller
        : (width < 600 ? 3 : 3); // Mobile: Always 3 columns for consistency

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        // Compact screens need taller tiles so the icon + label never overlap.
        childAspectRatio: isCompact ? 0.95 : 1.5,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return _buildQuickAccessTile(
          icon: tile['icon'] as IconData,
          label: tile['label'] as String,
          color: tile['color'] as Color,
          onTap: tile['onTap'] as VoidCallback,
          isCompact: isCompact,
        );
      },
    );
  }

  Widget _buildQuickAccessTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isCompact,
  }) {
    return MouseRegion(
      cursor: kIsWeb ? SystemMouseCursors.click : MouseCursor.defer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            vertical: isCompact ? 10 : 8,
            horizontal: 6,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 10 : 12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: isCompact ? 34 : 48,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: isCompact ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    final currency = NumberFormat.currency(symbol: 'NPR ', decimalDigits: 0);
    final timeFmt = DateFormat('MMM dd, hh:mm a');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: _recentActivity.isEmpty
            ? [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  'No recent activity',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your recent transactions will appear here',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ]
            : _recentActivity.map((a) {
                final dt = a.createdAt > 0
                    ? DateTime.fromMillisecondsSinceEpoch(a.createdAt)
                    : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: a.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(a.icon, color: a.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                a.subtitle,
                                if (dt != null) timeFmt.format(dt),
                              ].join(' • '),
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        currency.format(a.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }).toList(),
      ),
    );
  }

  // (cleanup) Removed unused create-user dialog from Dashboard.
}

class _ActivityItem {
  final int createdAt;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double amount;

  const _ActivityItem({
    required this.createdAt,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.amount,
  });
}
