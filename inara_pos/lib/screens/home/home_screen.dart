import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../orders/orders_screen.dart';
import '../menu/menu_screen.dart';
import '../tables/tables_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sales_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/inventory_screen.dart';
import '../customers/customers_screen.dart';
import '../purchases/purchases_screen.dart';
import '../expenses/expenses_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/responsive_wrapper.dart';
import '../../utils/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final Map<int, GlobalKey> _screenKeys = {
    0: GlobalKey(),
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
    4: GlobalKey(),
    5: GlobalKey(),
    6: GlobalKey(),
    7: GlobalKey(),
    8: GlobalKey(),
    9: GlobalKey(),
  };

  final List<String> _screenTitles = [
    'Dashboard',
    'Orders',
    'Tables',
    'Menu',
    'Sales',
    'Reports',
    'Inventory',
    'Customers',
    'Purchases',
    'Expenses',
  ];

  void _navigateToScreen(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _createScreen(int index) {
    switch (index) {
      case 0:
        return DashboardScreen(
          key: _screenKeys[0],
          onNavigate: _navigateToScreen,
        );
      case 1:
        return OrdersScreen(key: _screenKeys[1], hideAppBar: true);
      case 2:
        return TablesScreen(key: _screenKeys[2], hideAppBar: true);
      case 3:
        return MenuScreen(key: _screenKeys[3], hideAppBar: true);
      case 4:
        return SalesScreen(key: _screenKeys[4], hideAppBar: true);
      case 5:
        return ReportsScreen(key: _screenKeys[5], hideAppBar: true);
      case 6:
        return InventoryScreen(key: _screenKeys[6], hideAppBar: true);
      case 7:
        return CustomersScreen(key: _screenKeys[7], hideAppBar: true);
      case 8:
        return PurchasesScreen(key: _screenKeys[8], hideAppBar: true);
      case 9:
        return ExpensesScreen(key: _screenKeys[9], hideAppBar: true);
      default:
        return DashboardScreen(
          key: _screenKeys[0],
          onNavigate: _navigateToScreen,
        );
    }
  }

  List<Widget> get _screens => [
        _createScreen(0),
        _createScreen(1),
        _createScreen(2),
        _createScreen(3),
        _createScreen(4),
        _createScreen(5),
        _createScreen(6),
        _createScreen(7),
        _createScreen(8),
        _createScreen(9),
      ];

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // For small screens (including web on phones/PWA), use the compact mobile navigation
    // so we don't render an over-crowded web bottom bar.
    final isCompact = !kIsWeb || MediaQuery.of(context).size.width < 700;
    // (cleanup) mainNavItems was unused; selection logic uses _selectedIndex directly.

    return Scaffold(
      backgroundColor:
          const Color(0xFFFFFEF5), // Very light yellow/cream background
      appBar: _selectedIndex == 0
          ? null
          : AppBar(
              title: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.7), width: 1),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.jpeg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.local_cafe, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _screenTitles[_selectedIndex],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshCurrentScreen,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      drawer: isCompact ? _buildDrawer(context, authProvider) : null,
      body: kIsWeb
          ? ResponsiveWrapper(
              child: _screens[_selectedIndex],
              padding: EdgeInsets.zero, // Screens handle their own padding
            )
          : _screens[_selectedIndex],
      bottomNavigationBar: isCompact
          ? _buildMobileBottomNav(authProvider)
          : _buildWebBottomNav(authProvider),
    );
  }

  Widget _buildDrawer(BuildContext context, AuthProvider authProvider) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.logoPrimary,
                  AppTheme.logoSecondary,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'चिया गढी',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  authProvider.currentUsername ?? 'User',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  authProvider.isAdmin ? 'Admin' : 'Cashier',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          _buildDrawerTile(Icons.dashboard, 'Dashboard', 0),
          _buildDrawerTile(Icons.receipt_long, 'Orders', 1),
          _buildDrawerTile(Icons.table_restaurant, 'Tables', 2),
          _buildDrawerTile(Icons.restaurant_menu, 'Menu', 3),
          _buildDrawerTile(Icons.shopping_cart, 'Sales', 4),
          _buildDrawerTile(Icons.analytics, 'Reports', 5),
          _buildDrawerTile(Icons.inventory_2, 'Inventory', 6),
          _buildDrawerTile(Icons.people, 'Customers', 7),
          _buildDrawerTile(Icons.shopping_bag, 'Purchases', 8),
          _buildDrawerTile(Icons.payments, 'Expenses', 9),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showLogoutDialog(context, authProvider);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerTile(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.logoPrimary : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppTheme.logoPrimary : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  Widget _buildMobileBottomNav(AuthProvider authProvider) {
    // Mobile: Show only 4 most important items
    // In our screen list: 0=Dashboard, 1=Orders, 2=Tables, 3=Menu, 4+=More screens.
    // But mobile bottom nav shows: Home, Orders, Menu, More.
    final isMoreSelected = _selectedIndex == 2 || _selectedIndex > 3;

    int mobileIndexFromSelectedIndex(int selectedIndex) {
      switch (selectedIndex) {
        case 0:
          return 0; // Home
        case 1:
          return 1; // Orders
        case 3:
          return 2; // Menu
        default:
          return 3; // More
      }
    }

    int selectedIndexFromMobileIndex(int mobileIndex) {
      switch (mobileIndex) {
        case 0:
          return 0; // Home
        case 1:
          return 1; // Orders
        case 2:
          return 3; // Menu (NOT tables)
        default:
          return _selectedIndex;
      }
    }

    return NavigationBar(
      selectedIndex:
          isMoreSelected ? 3 : mobileIndexFromSelectedIndex(_selectedIndex),
      onDestinationSelected: (index) {
        if (index == 3) {
          // Show "More" bottom sheet
          _showMoreOptionsSheet(context, authProvider);
        } else {
          setState(() {
            _selectedIndex = selectedIndexFromMobileIndex(index);
          });
        }
      },
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 70,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long),
          selectedIcon: Icon(Icons.receipt_long),
          label: 'Orders',
        ),
        NavigationDestination(
          icon: Icon(Icons.restaurant_menu),
          selectedIcon: Icon(Icons.restaurant_menu),
          label: 'Menu',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more_horiz),
          label: 'More',
        ),
      ],
    );
  }

  void _showMoreOptionsSheet(BuildContext context, AuthProvider authProvider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildMoreOptionTile(context, Icons.table_restaurant, 'Tables', 2),
            _buildMoreOptionTile(context, Icons.shopping_cart, 'Sales', 4),
            _buildMoreOptionTile(context, Icons.analytics, 'Reports', 5),
            _buildMoreOptionTile(context, Icons.inventory_2, 'Inventory', 6),
            _buildMoreOptionTile(context, Icons.people, 'Customers', 7),
            _buildMoreOptionTile(context, Icons.shopping_bag, 'Purchases', 8),
            _buildMoreOptionTile(context, Icons.payments, 'Expenses', 9),
            _buildMoreOptionTile(context, Icons.settings, 'Settings', -1,
                isSettings: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreOptionTile(
      BuildContext context, IconData icon, String title, int index,
      {bool isSettings = false}) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.logoPrimary),
      title: Text(title),
      trailing: _selectedIndex == index && !isSettings
          ? Icon(Icons.check, color: AppTheme.logoPrimary)
          : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        if (isSettings) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else {
          setState(() {
            _selectedIndex = index;
          });
        }
      },
    );
  }

  Widget _buildWebBottomNav(AuthProvider authProvider) {
    // Web: Show all items
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 70,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dashboard),
          label: 'Home',
        ),
        const NavigationDestination(
          icon: Icon(Icons.receipt_long),
          label: 'Orders',
        ),
        const NavigationDestination(
          icon: Icon(Icons.table_restaurant),
          label: 'Tables',
        ),
        const NavigationDestination(
          icon: Icon(Icons.restaurant_menu),
          label: 'Menu',
        ),
        const NavigationDestination(
          icon: Icon(Icons.shopping_cart),
          label: 'Sales',
        ),
        const NavigationDestination(
          icon: Icon(Icons.analytics),
          label: 'Reports',
        ),
        const NavigationDestination(
          icon: Icon(Icons.inventory_2),
          label: 'Inventory',
        ),
        const NavigationDestination(
          icon: Icon(Icons.people),
          label: 'Customers',
        ),
        const NavigationDestination(
          icon: Icon(Icons.shopping_bag),
          label: 'Purchases',
        ),
        const NavigationDestination(
          icon: Icon(Icons.payments),
          label: 'Expenses',
        ),
      ],
    );
  }

  Future<void> _showLogoutDialog(
      BuildContext context, AuthProvider authProvider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      authProvider.logout();
      // Navigate to login screen
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/',
          (route) => false,
        );
      }
    }
  }

  void _refreshCurrentScreen() {
    // Recreate the current screen to trigger refresh
    setState(() {
      // Recreate screen widget which will trigger initState
      _screens[_selectedIndex] = _createScreen(_selectedIndex);
    });
  }
}
