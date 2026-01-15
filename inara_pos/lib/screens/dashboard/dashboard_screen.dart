import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
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
  // FIXED: Use ledger service instead of direct inventory service
  final InventoryLedgerService _ledgerService = InventoryLedgerService();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Get shop name from settings
      final settings = await dbProvider.query('settings');
      for (final setting in settings) {
        if (setting['key'] == 'cafe_name_en') {
          _shopName = setting['value'] as String? ?? 'Shop';
          break;
        }
      }

      // Get today's sales and credit
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).millisecondsSinceEpoch;

      final todayOrders = await dbProvider.query(
        'orders',
        where: 'created_at >= ? AND created_at <= ? AND payment_status IN (?, ?)',
        whereArgs: [startOfDay, endOfDay, 'paid', 'partial'],
      );

      if (!mounted) return;
      _todaySales = todayOrders.fold<double>(
        0.0,
        (sum, order) => sum + ((order['total_amount'] as num?)?.toDouble() ?? 0.0),
      );

      // Get today's credit from credit_transactions (matching customer credit section)
      final todayCreditTransactions = await dbProvider.query(
        'credit_transactions',
        where: 'created_at >= ? AND created_at <= ? AND transaction_type = ?',
        whereArgs: [startOfDay, endOfDay, 'credit'],
      );

      if (!mounted) return;
      _todayCredit = todayCreditTransactions.fold<double>(
        0.0,
        (sum, transaction) => sum + ((transaction['amount'] as num?)?.toDouble() ?? 0.0),
      );

      // FIXED: Calculate low stock count from ledger (not from inventory table)
      final products = await dbProvider.query(
        'products',
        where: 'is_sellable = ? OR is_sellable IS NULL',
        whereArgs: [1],
      );
      
      if (!mounted) return;
      final productIds = products
          .map((p) => p['id'])
          .where((id) => id != null)
          .toList()
          .cast<dynamic>();
      final stockMap = await _ledgerService.getCurrentStockBatch(
        context: context,
        productIds: productIds,
      );

      int lowStockCount = 0;
      for (final pid in productIds) {
        final currentStock = stockMap[pid] ?? 0.0;
        if (currentStock <= 0) lowStockCount++;
      }

      if (!mounted) return;
      _lowStockCount = lowStockCount;
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFEF5), // Very light yellow/cream background
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: kIsWeb
              ? ResponsiveWrapper(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildContent(context, authProvider),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  width: 80,
                  height: 80,
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, $_shopName',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Powered by Inara Tech',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey[500],
                          letterSpacing: 0.2,
                        ),
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
    ];
  }

  Widget _buildSummaryCards() {
    final currencyFormat = NumberFormat.currency(symbol: 'NPR ', decimalDigits: 0);
    
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
                      MaterialPageRoute(builder: (_) => const CustomersScreen()),
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

  Widget _buildLowStockAlert() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InventoryScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.warningColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warningColor.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Low Stock Alert',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warningColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_lowStockCount item${_lowStockCount == 1 ? '' : 's'} need restocking',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.warningColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.warningColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccessTiles(BuildContext context, AuthProvider authProvider) {
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
        'color': const Color(0xFF10B981),
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

    // Responsive grid: compact phones = 3 columns, tablets = 3, desktop = 4
    final crossAxisCount = isCompact
        ? 3
        : (kIsWeb ? (width > 1200 ? 4 : 3) : 2);
    
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
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
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
        children: [
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
        ],
      ),
    );
  }

  // (cleanup) Removed unused create-user dialog from Dashboard.
}
