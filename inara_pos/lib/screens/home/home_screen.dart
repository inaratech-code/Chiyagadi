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
  static const int _maxAliveScreens = 3;
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

  // PERF: Lazily create screens so we don't build/load everything at once.
  final Map<int, Widget> _screenCache = {};
  // PERF: Keep a small LRU set of screens mounted offstage so switching tabs
  // doesn't rebuild/reload and feels instant.
  final List<int> _alive = <int>[];

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

  void _navigateToScreen(int index) => _selectIndex(index);

  void _selectIndex(int index) async {
    // Role-based access control using permissions
    final auth = context.read<AuthProvider>();
    final hasAccess = await auth.hasAccessToSection(index);
    
    if (!hasAccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access denied: You do not have permission to access this section'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (index == _selectedIndex && _alive.contains(index)) return;
    setState(() {
      _selectedIndex = index;
      _ensureAlive(index);
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

  Widget _getScreen(int index) {
    return _screenCache.putIfAbsent(index, () => _createScreen(index));
  }

  void _ensureAlive(int index) {
    // Ensure widget exists
    _getScreen(index);

    // Update LRU list
    _alive.remove(index);
    _alive.add(index);

    // Evict oldest screens (but never evict the currently selected one)
    while (_alive.length > _maxAliveScreens) {
      final evict = _alive.first;
      if (evict == _selectedIndex) {
        // Move selected to the end and try again
        _alive.removeAt(0);
        _alive.add(evict);
        continue;
      }
      _alive.removeAt(0);
      _screenCache.remove(evict);
      _screenKeys[evict] = GlobalKey();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    // Ensure at least the current screen is alive.
    if (_alive.isEmpty || !_alive.contains(_selectedIndex)) {
      _ensureAlive(_selectedIndex);
    }

    // For small screens (including web on phones/PWA), use the compact mobile navigation
    // so we don't render an over-crowded web bottom bar.
    final isCompact = !kIsWeb || MediaQuery.of(context).size.width < 700;
    // (cleanup) mainNavItems was unused; selection logic uses _selectedIndex directly.

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
              child: _buildOffstageStack(),
              padding: EdgeInsets.zero, // Screens handle their own padding
            )
          : _buildOffstageStack(),
      bottomNavigationBar: isCompact
          ? _buildMobileBottomNav(authProvider)
          : _buildWebBottomNav(authProvider),
    );
  }

  Widget _buildOffstageStack() {
    // Keep only a few screens mounted to avoid layout cost explosion.
    // Offstage keeps state (scroll position, loaded data) while hidden.
    return Stack(
      children: [
        for (final i in _alive)
          Offstage(
            offstage: i != _selectedIndex,
            child: KeyedSubtree(
              key: ValueKey<int>(i),
              child: _getScreen(i),
            ),
          ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context, AuthProvider authProvider) {
    return Drawer(
      child: FutureBuilder<Set<int>>(
        future: authProvider.getRolePermissions(authProvider.currentUserRole ?? 'cashier'),
        builder: (context, snapshot) {
          final permissions = snapshot.data ?? <int>{0, 1, 2, 3, 4, 5, 7, 9};
          
          return ListView(
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
              if (permissions.contains(0))
                _buildDrawerTile(Icons.dashboard, 'Dashboard', 0),
              if (permissions.contains(1))
                _buildDrawerTile(Icons.receipt_long, 'Orders', 1),
              if (permissions.contains(2))
                _buildDrawerTile(Icons.table_restaurant, 'Tables', 2),
              if (permissions.contains(3))
                _buildDrawerTile(Icons.restaurant_menu, 'Menu', 3),
              if (permissions.contains(4))
                _buildDrawerTile(Icons.shopping_cart, 'Sales', 4),
              if (permissions.contains(5))
                _buildDrawerTile(Icons.analytics, 'Reports', 5),
              if (permissions.contains(6))
                _buildDrawerTile(Icons.inventory_2, 'Inventory', 6),
              if (permissions.contains(7))
                _buildDrawerTile(Icons.people, 'Customers', 7),
              if (permissions.contains(8))
                _buildDrawerTile(Icons.shopping_bag, 'Purchases', 8),
              if (permissions.contains(9))
                _buildDrawerTile(Icons.payments, 'Expenses', 9),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
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
          );
        },
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
        _selectIndex(index);
      },
    );
  }

  Widget _buildMobileBottomNav(AuthProvider authProvider) {
    // Mobile: Show only 4 most important items based on permissions
    // In our screen list: 0=Dashboard, 1=Orders, 2=Tables, 3=Menu, 4+=More screens.
    // Mobile bottom nav shows: Home, Orders (if permitted), Menu (if permitted), More.
    return FutureBuilder<Set<int>>(
      future: authProvider.getRolePermissions(authProvider.currentUserRole ?? 'cashier'),
      builder: (context, snapshot) {
        final permissions = snapshot.data ?? <int>{0, 1, 3}; // Default: Home, Orders, Menu
        
        // Ensure Dashboard (0) is always accessible
        final effectivePermissions = Set<int>.from(permissions);
        if (!effectivePermissions.contains(0)) {
          effectivePermissions.add(0);
        }
        
        // Determine if current selection is in "More" category
        final isMoreSelected = !effectivePermissions.contains(_selectedIndex) || 
                               (_selectedIndex == 2) || 
                               (_selectedIndex > 3);

        // Build destinations based on permissions
        final destinations = <NavigationDestination>[];
        final indexMap = <int, int>{}; // Map navigation index to section index
        int navIndex = 0;
        
        // Always add Home (Dashboard) - index 0
        destinations.add(const NavigationDestination(
          icon: Icon(Icons.dashboard),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Home',
        ));
        indexMap[navIndex] = 0;
        navIndex++;
        
        // Add Orders if permitted - index 1
        if (effectivePermissions.contains(1)) {
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.receipt_long),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ));
          indexMap[navIndex] = 1;
          navIndex++;
        }
        
        // Add Menu if permitted - index 3
        if (effectivePermissions.contains(3)) {
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.restaurant_menu),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Menu',
          ));
          indexMap[navIndex] = 3;
          navIndex++;
        }
        
        // Always add More button (NavigationBar requires at least 2, and we have Home + More minimum)
        destinations.add(const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more_horiz),
          label: 'More',
        ));
        final moreIndex = navIndex;

        // Calculate selected navigation index
        int selectedNavIndex = moreIndex; // Default to More
        if (!isMoreSelected) {
          // Find which navigation index corresponds to current section
          for (int i = 0; i < indexMap.length; i++) {
            if (indexMap[i] == _selectedIndex) {
              selectedNavIndex = i;
              break;
            }
          }
        }
        
        // Ensure selected index is valid
        selectedNavIndex = selectedNavIndex.clamp(0, destinations.length - 1);

        return NavigationBar(
          selectedIndex: selectedNavIndex,
          onDestinationSelected: (index) {
            if (index == moreIndex) {
              // Show "More" bottom sheet
              _showMoreOptionsSheet(context, authProvider);
            } else {
              // Navigate to the section mapped to this navigation index
              final sectionIndex = indexMap[index];
              if (sectionIndex != null) {
                _selectIndex(sectionIndex);
              }
            }
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 70,
          destinations: destinations,
        );
      },
    );
  }

  void _showMoreOptionsSheet(BuildContext context, AuthProvider authProvider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FutureBuilder<Set<int>>(
        future: authProvider.getRolePermissions(authProvider.currentUserRole ?? 'cashier'),
        builder: (context, snapshot) {
          final permissions = snapshot.data ?? <int>{};
          
          return SafeArea(
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
                if (permissions.contains(2))
                  _buildMoreOptionTile(context, Icons.table_restaurant, 'Tables', 2),
                if (permissions.contains(4))
                  _buildMoreOptionTile(context, Icons.shopping_cart, 'Sales', 4),
                if (permissions.contains(5))
                  _buildMoreOptionTile(context, Icons.analytics, 'Reports', 5),
                if (permissions.contains(6))
                  _buildMoreOptionTile(context, Icons.inventory_2, 'Inventory', 6),
                if (permissions.contains(7))
                  _buildMoreOptionTile(context, Icons.people, 'Customers', 7),
                if (permissions.contains(8))
                  _buildMoreOptionTile(context, Icons.shopping_bag, 'Purchases', 8),
                if (permissions.contains(9))
                  _buildMoreOptionTile(context, Icons.payments, 'Expenses', 9),
                _buildMoreOptionTile(context, Icons.settings, 'Settings', -1,
                    isSettings: true),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
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
          _selectIndex(index);
        }
      },
    );
  }

  Widget _buildWebBottomNav(AuthProvider authProvider) {
    // Web: Show items based on permissions
    return FutureBuilder<Set<int>>(
      future: authProvider.getRolePermissions(authProvider.currentUserRole ?? 'cashier'),
      builder: (context, snapshot) {
        final permissions = snapshot.data ?? <int>{};
        
        // Ensure Dashboard (0) is always accessible
        final effectivePermissions = permissions.isEmpty 
            ? {0, 1, 2, 3, 4, 5, 7, 9} // Default cashier permissions
            : permissions;
        if (!effectivePermissions.contains(0)) {
          effectivePermissions.add(0); // Always include Dashboard
        }
        
        // Build destinations based on permissions
        final destinations = <NavigationDestination>[];
        final sectionData = [
          {'icon': Icons.dashboard, 'label': 'Home', 'index': 0},
          {'icon': Icons.receipt_long, 'label': 'Orders', 'index': 1},
          {'icon': Icons.table_restaurant, 'label': 'Tables', 'index': 2},
          {'icon': Icons.restaurant_menu, 'label': 'Menu', 'index': 3},
          {'icon': Icons.shopping_cart, 'label': 'Sales', 'index': 4},
          {'icon': Icons.analytics, 'label': 'Reports', 'index': 5},
          {'icon': Icons.inventory_2, 'label': 'Inventory', 'index': 6},
          {'icon': Icons.people, 'label': 'Customers', 'index': 7},
          {'icon': Icons.shopping_bag, 'label': 'Purchases', 'index': 8},
          {'icon': Icons.payments, 'label': 'Expenses', 'index': 9},
        ];
        
        // Map original index to filtered index
        final indexMap = <int, int>{};
        int filteredIndex = 0;
        
        for (final section in sectionData) {
          final index = section['index'] as int;
          if (effectivePermissions.contains(index)) {
            destinations.add(NavigationDestination(
              icon: Icon(section['icon'] as IconData),
              label: section['label'] as String,
            ));
            indexMap[filteredIndex] = index;
            filteredIndex++;
          }
        }
        
        // NavigationBar requires at least 2 destinations
        // If we have fewer, ensure Dashboard and at least one other
        if (destinations.length < 2) {
          // Reset and add Dashboard + Orders as minimum
          destinations.clear();
          indexMap.clear();
          destinations.add(const NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Home',
          ));
          indexMap[0] = 0;
          
          // Add Orders if available, otherwise add Menu
          final fallbackIndex = effectivePermissions.contains(1) ? 1 : 3;
          if (fallbackIndex == 1) {
            destinations.add(const NavigationDestination(
              icon: Icon(Icons.receipt_long),
              label: 'Orders',
            ));
            indexMap[1] = 1;
          } else if (effectivePermissions.contains(3)) {
            destinations.add(const NavigationDestination(
              icon: Icon(Icons.restaurant_menu),
              label: 'Menu',
            ));
            indexMap[1] = 3;
          } else {
            // Last resort: add Orders anyway (admin can fix permissions)
            destinations.add(const NavigationDestination(
              icon: Icon(Icons.receipt_long),
              label: 'Orders',
            ));
            indexMap[1] = 1;
          }
        }
        
        // Find the selected index in the filtered list
        int selectedFilteredIndex = 0;
        for (int i = 0; i < destinations.length; i++) {
          if (indexMap[i] == _selectedIndex) {
            selectedFilteredIndex = i;
            break;
          }
        }
        
        return NavigationBar(
          selectedIndex: selectedFilteredIndex.clamp(0, destinations.length - 1),
          onDestinationSelected: (index) {
            final actualIndex = indexMap[index];
            if (actualIndex != null) {
              _selectIndex(actualIndex);
            }
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 70,
          destinations: destinations,
        );
      },
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
    // Recreate the current screen to trigger refresh.
    setState(() {
      _screenCache.remove(_selectedIndex);
      _screenKeys[_selectedIndex] = GlobalKey();
      _ensureAlive(_selectedIndex);
    });
  }
}
