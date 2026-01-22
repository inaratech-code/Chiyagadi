import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../models/category.dart';
import '../../models/product.dart';
import '../../services/order_service.dart';
import '../../widgets/order_overlay_widget.dart';
import '../../models/inventory_ledger_model.dart';
import '../../services/inventory_ledger_service.dart';
import '../../utils/theme.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;

class MenuScreen extends StatefulWidget {
  final bool hideAppBar;
  const MenuScreen({super.key, this.hideAppBar = false});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Category> _categories = [];
  List<Product> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // NEW: Quick order flow (cashier-friendly)
  final OrderService _orderService = OrderService();
  dynamic _activeOrderId;
  String? _activeOrderNumber;
  bool _isAddingToOrder = false;
  bool _showOrderOverlay = false; // UPDATED: Track overlay visibility
  int _overlayRefreshKey = 0; // UPDATED: Force overlay refresh

  // NEW: Delete menu item (soft delete)
  //
  // SECURITY/DATA INTEGRITY:
  // We intentionally do NOT hard-delete products because historical orders may reference them.
  // Instead we mark the product inactive + not sellable, which removes it from the menu.
  Future<void> _deleteMenuItem(Product product) async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    if (!auth.isAdmin) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete menu item?'),
        content: Text(
            'Delete "${product.name}"?\n\nThis will hide it from the menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final now = DateTime.now().millisecondsSinceEpoch;

      final where = kIsWeb ? 'documentId = ?' : 'id = ?';
      final id = kIsWeb ? product.documentId : product.id;
      if (id == null) throw Exception('Missing product id');

      await dbProvider.update(
        'products',
        values: {
          'is_active': 0,
          'is_sellable': 0,
          'updated_at': now,
        },
        where: where,
        whereArgs: [id],
      );

      if (!mounted) return;
      setState(() {
        _products.removeWhere((p) {
          final pid = kIsWeb ? p.documentId : p.id;
          return pid?.toString() == id.toString();
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Menu item deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  /// Seed menu items from chiyagaadi_menu_seed.dart
  Future<void> _seedMenuItems() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seed Menu Items?'),
        content: const Text(
          'This will add all menu items from the chalkboard menu to Firestore.\n\n'
          'Existing items will not be duplicated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Seed Menu'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seeding menu items...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      
      // Force re-initialization to reset any previous failures
      debugPrint('MenuScreen: Forcing database re-initialization for seed...');
      await dbProvider.forceInit();
      
      if (!dbProvider.isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Database not available. Please check Firebase connection and try refreshing the page.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        debugPrint('MenuScreen: Database still not available after forceInit()');
        return;
      }

      // Seed menu items
      debugPrint('MenuScreen: Starting menu seed...');
      final success = await dbProvider.seedMenuItems();
      
      if (!mounted) return;
      
      if (success) {
        debugPrint('MenuScreen: Seed completed successfully, reloading data...');
        
        // Wait a moment for Firestore to propagate
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Reload menu data
        await _loadData();
        
        // Verify data was loaded
        if (mounted) {
          if (_categories.isEmpty && _products.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Seed completed but no data loaded. Please refresh manually.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Menu items seeded successfully! Loaded ${_categories.length} categories and ${_products.length} products.'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        debugPrint('MenuScreen: Seed failed');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to seed menu items. Check console (F12) for details.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('MenuScreen: Error seeding menu items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _normalizeNameKey(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _defaultMenuImageForName(String name) {
    // PERF/WEB: The repo doesn't ship all per-item images yet (assets/images/menu/*).
    // Using missing assets triggers repeated 404 fetches while scrolling.
    // Use a single known-good asset so image decoding is cached and scrolling stays smooth.
    return 'assets/images/logo.jpeg';
  }

  dynamic _categoryIdForName(String categoryName) {
    final target = _normalizeNameKey(categoryName);
    for (final c in _categories) {
      if (_normalizeNameKey(c.name) == target) {
        return _getCategoryIdentifier(c);
      }
    }
    return null;
  }

  Color _categoryColorForName(String categoryName) {
    final key = _normalizeNameKey(categoryName);
    
    // Define colors for all categories
    if (key == _normalizeNameKey('Tuto Sip')) return const Color(0xFF4CAF50); // Green
    if (key == _normalizeNameKey('Chill Sip')) return const Color(0xFF2196F3); // Blue
    if (key == _normalizeNameKey('Snacks')) return const Color(0xFFFF9800); // Orange
    if (key == _normalizeNameKey('Hookah')) return const Color(0xFF9C27B0); // Purple
    if (key == _normalizeNameKey('Games & Vibes')) return const Color(0xFFE91E63); // Pink
    if (key == _normalizeNameKey('Smokes')) return const Color(0xFF424242); // Dark Gray
    if (key == _normalizeNameKey('Drinks')) return const Color(0xFF00BCD4); // Cyan
    
    // Default accent for any other categories
    return AppTheme.logoPrimary;
  }

  Widget _buildProductImage(String? imageUrl, String name) {
    final rawUrl = (imageUrl ?? '').trim();
    // UPDATED (perf/web): The repo does not ship per-item menu images under
    // `assets/images/menu/*` yet. Many seeded products have image_url pointing
    // there, which causes repeated 404 fetches on Flutter Web while scrolling.
    // Treat those paths as missing and fall back to a stable asset.
    final safeUrl = (kIsWeb &&
            (rawUrl.startsWith('assets/images/menu/') ||
                rawUrl.startsWith('assets/assets/images/menu/')))
        ? ''
        : rawUrl;

    final effectiveUrl = safeUrl.isEmpty
        ? _defaultMenuImageForName(name)
        : safeUrl;

    Widget fallback() => const Icon(Icons.image, size: 40, color: Colors.grey);

    if (effectiveUrl.startsWith('http')) {
      return Image.network(
        effectiveUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    if (effectiveUrl.startsWith('assets/')) {
      return Image.asset(
        effectiveUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    // Web: XFile from ImagePicker returns a blob/object URL which can be loaded via network.
    if (kIsWeb) {
      return Image.network(
        effectiveUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    return Image.file(
      io.File(effectiveUrl),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback(),
    );
  }

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadActiveOrder(); // Load active order for cashiers
    });
  }

  bool _isOrderMode(InaraAuthProvider auth) {
    // NEW: Cashier uses Menu as ordering surface (admin keeps menu management).
    return !auth.isAdmin;
  }

  Future<void> _loadActiveOrder() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // UPDATED: Query by status only, filter order_type in-memory to avoid Firestore composite index
      final orders = await dbProvider.query(
        'orders',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'created_at DESC',
        limit: 50, // Get recent pending orders, filter in-memory
      );

      // Filter for dine_in orders in-memory
      final dineInOrders = orders.where((o) => o['order_type'] == 'dine_in').toList();

      if (dineInOrders.isNotEmpty) {
        final order = dineInOrders.first; // Most recent dine_in pending order
        // UPDATED: Firestore query returns 'id' field (not 'documentId'), use 'id' for both web and mobile
        // Debug: Check all possible ID fields
        debugPrint('MenuScreen: Order keys: ${order.keys.toList()}');
        debugPrint('MenuScreen: Order id field: ${order['id']}, documentId field: ${order['documentId']}');
        _activeOrderId = order['id'] ?? order['documentId'];
        _activeOrderNumber = order['order_number'] as String?;
        debugPrint('MenuScreen: Loaded active order - ID: $_activeOrderId, Number: $_activeOrderNumber');
      } else {
        _activeOrderId = null;
        _activeOrderNumber = null;
        debugPrint('MenuScreen: No active order found');
      }
    } catch (e) {
      debugPrint('MenuScreen: Error loading active order: $e');
      // Ignore errors but log them
    }
  }

  Future<void> _addToOrder(Product product) async {
    if (_isAddingToOrder) {
      debugPrint('Already adding item, skipping...');
      return;
    }
    debugPrint('Adding ${product.name} to order...');
    setState(() => _isAddingToOrder = true);

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      await dbProvider.init();

      // UPDATED: Try to load active order first, but if query fails, we'll create a new one
      // The query might fail due to Firestore index issues, so we handle that gracefully
      try {
        await _loadActiveOrder();
      } catch (e) {
        debugPrint('MenuScreen: Error loading active order (will create new if needed): $e');
        // Continue - we'll create a new order if _activeOrderId is still null
      }

      // Ensure an order exists - create new only if none found
      if (_activeOrderId == null) {
        debugPrint('MenuScreen: No active order found, creating new order...');
        final createdBy = auth.currentUserId != null
            ? (kIsWeb
                ? auth.currentUserId!
                : int.tryParse(auth.currentUserId!))
            : null;

        _activeOrderId = await _orderService.createOrder(
          dbProvider: dbProvider,
          orderType: 'dine_in',
          createdBy: createdBy,
        );

        final order = await _orderService.getOrderById(dbProvider, _activeOrderId);
        _activeOrderNumber = order?.orderNumber ?? 'Order';
        debugPrint('MenuScreen: Created new order - ID: $_activeOrderId, Number: $_activeOrderNumber');
        
        // UPDATED: Store the order ID in state immediately so it persists
        if (mounted) {
          setState(() {
            // State is already updated above, but ensure it's persisted
          });
        }
      } else {
        debugPrint('MenuScreen: Using existing order - ID: $_activeOrderId');
      }

      final createdBy = auth.currentUserId != null
          ? (kIsWeb ? auth.currentUserId! : int.tryParse(auth.currentUserId!))
          : null;

      await _orderService.addItemToOrder(
        dbProvider: dbProvider,
        context: context,
        orderId: _activeOrderId,
        product: product,
        quantity: 1,
        createdBy: createdBy,
      );

      if (mounted) {
        // UPDATED: Don't reload active order - we already have the correct order ID
        // The order ID is set when creating/loading the order above
        
        // UPDATED: Always increment refresh key to ensure overlay shows latest items
        // Also ensure overlay is shown if items are being added
        setState(() {
          _overlayRefreshKey++; // Increment to force overlay refresh
          // Auto-show overlay when items are added (if not already shown)
          if (!_showOrderOverlay && _activeOrderId != null) {
            _showOrderOverlay = true;
          }
        });
        
        debugPrint('MenuScreen: After adding item - Order ID: $_activeOrderId, Overlay shown: $_showOrderOverlay');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${product.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error adding item to order: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to add item: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingToOrder = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Check if database is available
      if (!dbProvider.isAvailable) {
        debugPrint('MenuScreen: Database not available, attempting to force reinitialize...');
        
        // Try to force reinitialize with multiple attempts
        bool initSuccess = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            debugPrint('MenuScreen: Force init attempt $attempt/3...');
            await dbProvider.forceInit();
            
            // Wait a moment for initialization to complete
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Test the connection to verify it actually works
            final connectionTest = await dbProvider.testConnection();
            
            if (connectionTest && dbProvider.isAvailable) {
              debugPrint('MenuScreen: Database available and connection test passed (attempt $attempt)');
              initSuccess = true;
              break;
            } else {
              debugPrint('MenuScreen: Database still not available after attempt $attempt (connection test: $connectionTest)');
              if (attempt < 3) {
                // Wait longer before next attempt
                await Future.delayed(Duration(milliseconds: 1000 * attempt));
              }
            }
          } catch (e) {
            debugPrint('MenuScreen: Error during force reinitialize attempt $attempt: $e');
            if (attempt < 3) {
              await Future.delayed(Duration(milliseconds: 1000 * attempt));
            }
          }
        }
        
        if (!initSuccess) {
          debugPrint('MenuScreen: Database still not available after all retry attempts');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Database not available. Tap to retry connection.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 10),
                action: SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () async {
                    // Force reinitialize and reload
                    final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
                    await dbProvider.forceInit();
                    await Future.delayed(const Duration(milliseconds: 500));
                    _loadData(); // Retry loading
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      debugPrint('MenuScreen: Loading categories and products...');

      // PERF: Categories + products can load in parallel.
      final categoryFuture = dbProvider.query(
        'categories',
        orderBy: 'display_order ASC',
      );

      final productFuture = () async {
        // PERF/Web: avoid complex SQL (OR/IS NULL) on Firestore; fetch sellable and sort/filter in memory.
        if (kIsWeb) {
          // First try the fast path: explicitly sellable.
          final sellable = await dbProvider.query(
            'products',
            where: 'is_sellable = ?',
            whereArgs: [1],
          );
          debugPrint('MenuScreen: Found ${sellable.length} sellable products');
          if (sellable.isNotEmpty) return sellable;

          // Fallback for legacy docs (missing is_sellable): fetch all and filter.
          final all = await dbProvider.query('products');
          debugPrint('MenuScreen: Found ${all.length} total products, filtering...');
          final filtered = all.where((p) {
            final v = p['is_sellable'];
            return v == null || v == 1;
          }).toList();
          debugPrint('MenuScreen: After filtering: ${filtered.length} products');
          return filtered;
        }

        return await dbProvider.query(
          'products',
          where:
              'is_sellable = ? OR (is_sellable IS NULL OR is_sellable = 1)', // SQLite supports this
          whereArgs: [1],
        );
      }();

      final results = await Future.wait<List<Map<String, dynamic>>>([
        categoryFuture,
        productFuture,
      ]);

      final categoryMaps = results[0];
      final productMaps = results[1];

      debugPrint('MenuScreen: Loaded ${categoryMaps.length} categories and ${productMaps.length} products');

      _categories = categoryMaps.map((map) => Category.fromMap(map)).toList();
      _products = productMaps.map((map) => Product.fromMap(map)).toList();
      
      debugPrint('MenuScreen: Parsed ${_categories.length} categories and ${_products.length} products');
      
      if (_categories.isEmpty && _products.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No menu items found. Click the seed button to add menu items.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('MenuScreen: Error loading menu data: $e');
      debugPrint('MenuScreen: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading menu: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) {
      return _products;
    }
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (p.description != null &&
                p.description!
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase())))
        .toList();
  }

  // Group products by category
  Map<Category, List<Product>> get _productsByCategory {
    final Map<String, Category> categoryMap = {};
    final Map<String, List<Product>> grouped = {};

    // Create a map of category IDs to Category objects
    for (final cat in _categories) {
      final catId = _getCategoryIdentifier(cat);
      if (catId != null) {
        categoryMap[catId.toString()] = cat;
      }
    }

    // Create "Uncategorized" category
    final uncategorized = Category(
      name: 'Uncategorized',
      displayOrder: 9999,
      isActive: true,
      isLocked: false,
      createdAt: 0,
      updatedAt: 0,
    );

    // Group products by category
    for (final product in _filteredProducts) {
      String categoryKey = 'uncategorized';

      if (product.categoryId != null) {
        final catIdStr = product.categoryId.toString();
        if (categoryMap.containsKey(catIdStr)) {
          categoryKey = catIdStr;
        }
      }

      if (!grouped.containsKey(categoryKey)) {
        grouped[categoryKey] = [];
      }
      grouped[categoryKey]!.add(product);
    }

    // Convert to Map<Category, List<Product>> and sort by display order
    final result = <Category, List<Product>>{};
    for (final entry in grouped.entries) {
      Category cat;
      if (entry.key == 'uncategorized') {
        cat = uncategorized;
      } else {
        cat = categoryMap[entry.key]!;
      }
      result[cat] = entry.value;
    }

    // Sort categories by display order
    final sortedKeys = result.keys.toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final sortedMap = <Category, List<Product>>{};
    for (final cat in sortedKeys) {
      sortedMap[cat] = result[cat]!;
    }

    return sortedMap;
  }

  // Helper method to get category identifier (int for SQLite, String for Firestore)
  dynamic _getCategoryIdentifier(Category category) {
    if (kIsWeb) {
      return category.documentId ?? category.id;
    }
    return category.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              elevation: 0,
              title: const Text(
                'Menu Management',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                // Seed menu items button (admin only)
                Consumer<InaraAuthProvider>(
                  builder: (context, auth, _) {
                    if (auth.isAdmin) {
                      return IconButton(
                        icon: const Icon(Icons.restaurant_menu),
                        onPressed: () => _seedMenuItems(),
                        tooltip: 'Seed Menu Items',
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.category),
                  onPressed: () => _showAddCategoryDialog(),
                  tooltip: 'Add Category',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      body: Stack(
        children: [
          Column(
        children: [
          // Category Section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.logoLight.withOpacity(0.22),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.logoSecondary.withOpacity(0.25),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.category, color: AppTheme.logoPrimary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddCategoryDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Category'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.logoPrimary,
                  ),
                ),
              ],
            ),
          ),
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search menu items...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Menu Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.restaurant_menu,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No menu items found'
                                  : 'No items match your search',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showAddProductDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Menu Item'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                            : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _productsByCategory.isEmpty
                            ? const SizedBox.shrink()
                            : ListView.builder(
                                padding: EdgeInsets.only(
                                  left: 8,
                                  right: 8,
                                  top: 8,
                                  bottom: kIsWeb ? 8 : 120, // Increased bottom padding on mobile to prevent FAB overlap
                                ),
                                itemCount: _productsByCategory.length,
                                itemBuilder: (context, categoryIndex) {
                                  final category = _productsByCategory.keys
                                      .elementAt(categoryIndex);
                                  final categoryProducts =
                                      _productsByCategory[category]!;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Category Heading (with top margin to prevent overlap)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          left: 8,
                                          right: 8,
                                          top: categoryIndex == 0 ? 10 : 20, // Extra top margin for non-first categories
                                          bottom: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: _categoryColorForName(category.name)
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: _categoryColorForName(category.name),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  category.name.toUpperCase(),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: _categoryColorForName(category.name),
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '(${categoryProducts.length} items)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                            Builder(
                                              builder: (context) {
                                                final auth = Provider.of<InaraAuthProvider>(context, listen: false);
                                                if (!auth.isAdmin) return const SizedBox.shrink();
                                                return Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      icon: const Icon(Icons.edit, size: 18),
                                                      onPressed: () => _showEditCategoryDialog(category),
                                                      tooltip: 'Edit Category',
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      color: Colors.grey[600],
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Products Grid for this category
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          // UPDATED: 3 columns for mobile (Android/iOS) as per design reference
                                          crossAxisCount: () {
                                            final width = MediaQuery.of(context).size.width;
                                            if (!kIsWeb && width < 900) return 3; // Mobile (Android/iOS): 3 columns
                                            if (width < 600) return 3; // Mobile web: 3 columns
                                            if (width < 900) return 4; // Tablet: 4 columns
                                            if (width < 1200) return 5; // Desktop: 5 columns
                                            return 6; // Large desktop: 6 columns
                                          }(),
                                          // UPDATED: Aspect ratio optimized for 3-column layout - adjusted for better spacing
                                          childAspectRatio: () {
                                            final width = MediaQuery.of(context).size.width;
                                            if (!kIsWeb && width < 900) return 0.68; // Mobile (Android/iOS): taller to accommodate all elements
                                            if (width < 600) return 0.68; // Mobile web: taller to accommodate all elements
                                            return 0.75; // Web/Tablet: taller cards
                                          }(),
                                          crossAxisSpacing: 8,
                                          mainAxisSpacing: 8,
                                        ),
                                        itemCount: categoryProducts.length,
                                        itemBuilder: (context, productIndex) {
                                          final product =
                                              categoryProducts[productIndex];
                                          return _buildProductCard(product);
                                        },
                                      ),
                                      // Increased spacing between categories to prevent overlap
                                      SizedBox(height: !kIsWeb ? 32 : 20),
                                    ],
                                  );
                                },
                              ),
                      ),
          ),
        ],
          ),
          // UPDATED: Semi-transparent backdrop on left side only (menu area) - allows menu clicks
          // Responsive: Full screen on mobile, side panel on larger screens
          if (_showOrderOverlay && _activeOrderId != null)
            Builder(
              builder: (context) {
                final screenWidth = MediaQuery.of(context).size.width;
                final isMobile = screenWidth < 600;
                final panelWidth = isMobile ? screenWidth : screenWidth * 0.45;
                
                return Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: isMobile ? 0 : panelWidth, // Full screen backdrop on mobile
                  child: IgnorePointer(
                    // UPDATED: Ignore pointer events so menu items remain fully clickable
                    ignoring: true,
                    child: Container(
                      color: Colors.black.withOpacity(isMobile ? 0.3 : 0.1), // Darker on mobile
                    ),
                  ),
                );
              },
            ),
          // UPDATED: Order overlay as side panel (desktop) or bottom sheet (mobile) - allows menu interaction
          if (_showOrderOverlay && _activeOrderId != null)
            Builder(
              builder: (context) {
                final screenWidth = MediaQuery.of(context).size.width;
                final isMobile = screenWidth < 600;
                final panelWidth = isMobile ? screenWidth : screenWidth * 0.45;
                
                if (isMobile) {
                  // Mobile: Bottom sheet style (takes 70% of screen height)
                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Material(
                      elevation: 16,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      color: Colors.white,
                      child: OrderOverlayWidget(
                        key: ValueKey('${_activeOrderId}_$_overlayRefreshKey'),
                        orderId: _activeOrderId,
                        orderNumber: _activeOrderNumber ?? 'Order',
                        refreshKey: _overlayRefreshKey,
                        onClose: () {
                          setState(() => _showOrderOverlay = false);
                        },
                        onOrderUpdated: () async {
                          await _loadActiveOrder();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  );
                } else {
                  // Desktop/Tablet: Side panel
                  return Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: panelWidth,
                    child: Material(
                      elevation: 8,
                      color: Colors.white,
                      child: OrderOverlayWidget(
                        key: ValueKey('${_activeOrderId}_$_overlayRefreshKey'),
                        orderId: _activeOrderId,
                        orderNumber: _activeOrderNumber ?? 'Order',
                        refreshKey: _overlayRefreshKey,
                        onClose: () {
                          setState(() => _showOrderOverlay = false);
                        },
                        onOrderUpdated: () async {
                          await _loadActiveOrder();
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
      floatingActionButton: _showOrderOverlay ? null : Consumer<InaraAuthProvider>(
        builder: (context, auth, _) {
          // UPDATED: Show "View Order" button when there's an active order (for all users)
          // Cashiers can also create new orders, admins can view existing orders
          if (_activeOrderId != null || _isOrderMode(auth)) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: !kIsWeb ? 80 : 0, // Extra bottom padding on mobile to avoid overlap with bottom nav
                right: !kIsWeb ? 8 : 0, // Slight right padding to avoid edge overlap
              ),
              child: FloatingActionButton.extended(
                onPressed: _isAddingToOrder
                    ? null
                    : () async {
                        // If no active order and user is cashier, create one first
                        if (_activeOrderId == null && _isOrderMode(auth)) {
                          try {
                            final dbProvider =
                                Provider.of<UnifiedDatabaseProvider>(context, listen: false);
                            final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
                            await dbProvider.init();

                            final createdBy = authProvider.currentUserId != null
                                ? (kIsWeb
                                    ? authProvider.currentUserId!
                                    : int.tryParse(authProvider.currentUserId!))
                                : null;

                            _activeOrderId = await _orderService.createOrder(
                              dbProvider: dbProvider,
                              orderType: 'dine_in',
                              createdBy: createdBy,
                            );

                            final order = await _orderService.getOrderById(dbProvider, _activeOrderId);
                            _activeOrderNumber = order?.orderNumber ?? 'Order';
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error creating order: $e')),
                              );
                            }
                            return;
                          }
                        }

                        // UPDATED: Load active order before showing overlay to ensure correct order ID
                        if (_activeOrderId == null) {
                          await _loadActiveOrder();
                        }
                        
                        // Show overlay if we have an active order
                        if (mounted && _activeOrderId != null) {
                          setState(() {
                            _showOrderOverlay = true;
                            _overlayRefreshKey++; // Force overlay to reload with latest data
                          });
                        }
                      },
                backgroundColor: AppTheme.logoPrimary,
                icon: const Icon(Icons.receipt_long),
                label: Text(_isAddingToOrder
                    ? 'Please wait…'
                    : (_activeOrderId == null ? 'New Order' : 'View Order')),
              ),
            );
          }

          // Admin: keep existing menu management
          return Padding(
            padding: EdgeInsets.only(
              bottom: !kIsWeb ? 80 : 0, // Extra bottom padding on mobile to avoid overlap with bottom nav
              right: !kIsWeb ? 8 : 0, // Slight right padding to avoid edge overlap
            ),
            child: FloatingActionButton.extended(
              onPressed: () => _showAddProductDialog(),
              backgroundColor: Theme.of(context).primaryColor,
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.none, // UPDATED: Don't clip so edit button is visible
      child: Stack(
        children: [
          InkWell(
            // UPDATED: Tap to add to order, long-press for admins to edit
            onTap: () {
              // Always add menu items to order when clicked
              _addToOrder(product);
            },
            onLongPress: () {
              // UPDATED: Long-press to edit menu items
              _showEditProductDialog(product);
            },
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // UPDATED: Square/near-square product image (inspired by design reference)
                AspectRatio(
                  aspectRatio: 1.0, // Square image for consistent 3-column layout
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      child: _buildProductImage(product.imageUrl, product.name),
                    ),
                  ),
                ),

                // UPDATED: Content area - name and price (improved spacing to prevent overlap)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Item name (single line, clear and visible)
                        Text(
                          product.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: () {
                              final width = MediaQuery.of(context).size.width;
                              if (!kIsWeb && width < 900) return 12.0; // Mobile (Android/iOS): compact for 3 columns
                              if (width < 600) return 12.0; // Mobile web: compact
                              return 14.0; // Web: slightly larger
                            }(),
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 6),

                        // Price (prominent, single line) - with bottom margin to separate from action bar
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'रू${product.price.toStringAsFixed(0)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: () {
                                final width = MediaQuery.of(context).size.width;
                                if (!kIsWeb && width < 900) return 13.0; // Mobile (Android/iOS): compact but visible
                                if (width < 600) return 13.0; // Mobile web: compact
                                return 15.0; // Web: standard size
                              }(),
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // NEW: Action bar at bottom using app's primary color (with clear separation)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.logoPrimary, // Using app's golden yellow color
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    '< रू${product.price.toStringAsFixed(0)} >',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: () {
                        final width = MediaQuery.of(context).size.width;
                        if (!kIsWeb && width < 900) return 12.0; // Mobile (Android/iOS): compact
                        if (width < 600) return 12.0; // Mobile web: compact
                        return 14.0; // Web: standard size
                      }(),
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // UPDATED: Edit icon button - positioned in top-right corner of card (available for all users)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              elevation: 3,
              color: Colors.blue,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                onTap: () => _showEditProductDialog(product),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.edit,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get current stock for a product
  Future<double> _getProductStock(Product product) async {
    try {
      final productId = kIsWeb ? product.documentId : product.id;
      if (productId == null) return 0.0;
      
      final ledgerService = InventoryLedgerService();
      return await ledgerService.getCurrentStock(
        context: context,
        productId: productId,
      );
    } catch (e) {
      debugPrint('Error getting product stock: $e');
      return 0.0;
    }
  }

  Future<bool?> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    bool isActive = true;
    String? categoryName;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                Icons.category,
                color: AppTheme.logoPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Add Category',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You need to add a category before adding products.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g., Beverages, Food, Snacks',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.label),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppTheme.logoPrimary, width: 2),
                    ),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() => isActive = value ?? true);
                      },
                    ),
                    const Text('Active'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a category name'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'isActive': isActive,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.logoPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Category'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'] != null) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final now = DateTime.now().millisecondsSinceEpoch;
        categoryName = result['name'] as String;
        final categoryIsActive = result['isActive'] as bool;

        // Get the max display_order to add new category at the end
        final existingCategories = await dbProvider.query('categories');
        final normalizedNew = _normalizeNameKey(categoryName);
        final isDuplicate = existingCategories.any((c) {
          final existingName = (c['name'] as String?) ?? '';
          return _normalizeNameKey(existingName) == normalizedNew;
        });
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Category "$categoryName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return false;
        }

        final maxOrder = existingCategories.isEmpty
            ? 0
            : (existingCategories
                    .map((c) => c['display_order'] as int? ?? 0)
                    .reduce((a, b) => a > b ? a : b) +
                1);

        await dbProvider.insert('categories', {
          'name': categoryName,
          'display_order': maxOrder,
          'is_active': categoryIsActive ? 1 : 0,
          'is_locked': 0,
          'created_at': now,
          'updated_at': now,
        });

        await _loadData(); // Reload data to show new category

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Category "$categoryName" added successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding category: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return false;
      }
    }
    return false;
  }

  Future<void> _showEditCategoryDialog(Category category) async {
    final nameController = TextEditingController(text: category.name);
    bool isActive = category.isActive;
    final originalName = category.name;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                Icons.edit,
                color: AppTheme.logoPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Edit Category',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g., Beverages, Food, Snacks',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.label),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppTheme.logoPrimary, width: 2),
                    ),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() => isActive = value ?? true);
                      },
                    ),
                    const Text('Active'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a category name'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'isActive': isActive,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.logoPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'] != null) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await dbProvider.init();
        final now = DateTime.now().millisecondsSinceEpoch;
        final categoryName = result['name'] as String;
        final categoryIsActive = result['isActive'] as bool;

        // Check for duplicate (excluding current category)
        final existingCategories = await dbProvider.query('categories');
        final normalizedNew = _normalizeNameKey(categoryName);
        final categoryId = _getCategoryIdentifier(category);
        
        final isDuplicate = existingCategories.any((c) {
          final existingId = kIsWeb ? c['documentId'] : c['id'];
          // Skip current category
          if (existingId.toString() == categoryId.toString()) return false;
          final existingName = (c['name'] as String?) ?? '';
          return _normalizeNameKey(existingName) == normalizedNew;
        });
        
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Category "$categoryName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        final where = kIsWeb ? 'documentId = ?' : 'id = ?';
        await dbProvider.update(
          'categories',
          values: {
            'name': categoryName,
            'is_active': categoryIsActive ? 1 : 0,
            'updated_at': now,
          },
          where: where,
          whereArgs: [categoryId],
        );

        await _loadData(); // Reload data to show updated category

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Category "$categoryName" updated successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating category: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _showAddProductDialog() async {
    if (_categories.isEmpty) {
      // Show dialog to add a category first
      final categoryAdded = await _showAddCategoryDialog();
      if (categoryAdded == true) {
        // Reload categories and then show add product dialog
        await _loadData();
        // Retry showing add product dialog if categories are now available
        if (_categories.isNotEmpty) {
          await _showAddProductDialog();
        }
      }
      return;
    }

    final nameController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();
    final imageUrlController = TextEditingController();
    dynamic selectedCategoryId = _getCategoryIdentifier(_categories.first);
    bool isVeg = true;
    bool isActive = true;
    XFile? selectedImageFile; // Use XFile which works on both platforms

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Menu Item',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Price and Category Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          decoration: const InputDecoration(
                            labelText: 'Price (NPR) *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<dynamic>(
                          value: selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          items: _categories.map((cat) {
                            final catId = _getCategoryIdentifier(cat);
                            return DropdownMenuItem(
                              value: catId,
                              child: Text(cat.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() => selectedCategoryId = value);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Image Upload Section
                  Text(
                    'Product Image',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: selectedImageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: kIsWeb
                                      ? Image.network(
                                          selectedImageFile!.path,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          io.File(selectedImageFile!.path),
                                          fit: BoxFit.cover,
                                        ),
                                )
                              : imageUrlController.text.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        imageUrlController.text,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Center(
                                            child: Icon(Icons.image,
                                                size: 48, color: Colors.grey),
                                          );
                                        },
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image,
                                          size: 48, color: Colors.grey),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          if (selectedImageFile != null ||
                              imageUrlController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  selectedImageFile = null;
                                  imageUrlController.clear();
                                });
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Remove'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Or enter Image URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        setDialogState(() {
                          selectedImageFile = null;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Description
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),

                  const SizedBox(height: 16),

                  // Checkboxes
                  Row(
                    children: [
                      Checkbox(
                        value: isVeg,
                        onChanged: (value) {
                          setDialogState(() => isVeg = value ?? true);
                        },
                      ),
                      const Text('Vegetarian'),
                      const SizedBox(width: 24),
                      Checkbox(
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() => isActive = value ?? true);
                        },
                      ),
                      const Text('Available'),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quick category toggles (Smokes / Drinks) – checkbox + color only
                  Row(
                    children: [
                      Tooltip(
                        message: 'Smokes',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Smokes')?.toString(),
                              onChanged: (v) {
                                final smokesId = _categoryIdForName('Smokes');
                                if (smokesId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = smokesId;
                                  } else {
                                    selectedCategoryId = _getCategoryIdentifier(
                                        _categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Smokes'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SM',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Tooltip(
                        message: 'Drinks',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Drinks')?.toString(),
                              onChanged: (v) {
                                final drinksId = _categoryIdForName('Drinks');
                                if (drinksId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = drinksId;
                                  } else {
                                    selectedCategoryId = _getCategoryIdentifier(
                                        _categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Drinks'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'DR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Add Item'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true &&
        nameController.text.isNotEmpty &&
        priceController.text.isNotEmpty &&
        selectedCategoryId != null) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;

        // Disallow duplicate menu item names (case-insensitive).
        final newName = nameController.text.trim();
        final normalizedNew = _normalizeNameKey(newName);
        final isDuplicate =
            _products.any((p) => _normalizeNameKey(p.name) == normalizedNew);
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Menu item "$newName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        String? finalImageUrl = imageUrlController.text.trim().isEmpty
            ? null
            : imageUrlController.text.trim();

        // If image was uploaded, copy it to app directory and use local path
        if (selectedImageFile != null && !kIsWeb) {
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final imageDir = io.Directory('${appDir.path}/product_images');
            if (!await imageDir.exists()) {
              await imageDir.create(recursive: true);
            }
            final fileName =
                '${now}_${nameController.text.trim().replaceAll(' ', '_')}.jpg';
            final savedImage = await io.File(selectedImageFile!.path)
                .copy('${imageDir.path}/$fileName');
            finalImageUrl = savedImage.path;
          } catch (e) {
            debugPrint('Error saving image: $e');
          }
        }

        // Auto-assign image by name if none provided.
        finalImageUrl ??= _defaultMenuImageForName(newName);

        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        // Check if database is available
        if (!dbProvider.isAvailable) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Database not available. Please check Firebase connection.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        final productId = await dbProvider.insert('products', {
          'category_id': selectedCategoryId,
          'name': newName,
          'description': descController.text.trim().isEmpty
              ? null
              : descController.text.trim(),
          'price': double.parse(priceController.text),
          'cost': 0,
          'image_url': finalImageUrl,
          'is_veg': isVeg ? 1 : 0,
          'is_active': isActive ? 1 : 0,
          'is_purchasable': 0, // Menu items are not purchasable by default
          'is_sellable': 1, // Menu items are sellable
          'created_at': now,
          'updated_at': now,
        });
        
        if (productId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to add product. Database may not be available.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        debugPrint('MenuScreen: Product added with ID: $productId');
        await _loadData(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product added successfully'),
              backgroundColor: AppTheme.successColor,
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

  Future<void> _showEditProductDialog(Product product) async {
    final nameController = TextEditingController(text: product.name);
    final descController =
        TextEditingController(text: product.description ?? '');
    final priceController =
        TextEditingController(text: product.price.toString());
    final imageUrlController =
        TextEditingController(text: product.imageUrl ?? '');
    // Find the category that matches this product's categoryId
    final matchingCategory = _categories.firstWhere(
      (c) {
        final catId = _getCategoryIdentifier(c);
        return catId.toString() == product.categoryId.toString();
      },
      orElse: () => _categories.isNotEmpty
          ? _categories.first
          : Category(
              name: 'Unknown',
              createdAt: 0,
              updatedAt: 0,
            ),
    );
    dynamic selectedCategoryId = _getCategoryIdentifier(matchingCategory);
    bool isVeg = product.isVeg;
    bool isActive = product.isActive;
    XFile? selectedImageFile; // Use XFile which works on both platforms

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Menu Item',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Price and Category Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          decoration: const InputDecoration(
                            labelText: 'Price (NPR) *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<dynamic>(
                          value: selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          items: _categories.map((cat) {
                            final catId = _getCategoryIdentifier(cat);
                            return DropdownMenuItem(
                              value: catId,
                              child: Text(cat.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() => selectedCategoryId = value);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Image Upload Section
                  Text(
                    'Product Image',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: selectedImageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: kIsWeb
                                      ? Image.network(
                                          selectedImageFile!.path,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          io.File(selectedImageFile!.path),
                                          fit: BoxFit.cover,
                                        ),
                                )
                              : imageUrlController.text.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: imageUrlController.text
                                              .startsWith('http')
                                          ? Image.network(
                                              imageUrlController.text,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return const Center(
                                                  child: Icon(Icons.image,
                                                      size: 48,
                                                      color: Colors.grey),
                                                );
                                              },
                                            )
                                          : kIsWeb
                                              ? Image.network(
                                                  imageUrlController.text,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Center(
                                                      child: Icon(Icons.image,
                                                          size: 48,
                                                          color: Colors.grey),
                                                    );
                                                  },
                                                )
                                              : Image.file(
                                                  io.File(
                                                      imageUrlController.text),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Center(
                                                      child: Icon(Icons.image,
                                                          size: 48,
                                                          color: Colors.grey),
                                                    );
                                                  },
                                                ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image,
                                          size: 48, color: Colors.grey),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          if (selectedImageFile != null ||
                              imageUrlController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  selectedImageFile = null;
                                  imageUrlController.clear();
                                });
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Remove'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Or enter Image URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        setDialogState(() {
                          selectedImageFile = null;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Description
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 12),

                  // Checkboxes
                  Row(
                    children: [
                      Checkbox(
                        value: isVeg,
                        onChanged: (value) {
                          setDialogState(() => isVeg = value ?? true);
                        },
                      ),
                      const Text('Vegetarian'),
                      const SizedBox(width: 16),
                      Checkbox(
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() => isActive = value ?? true);
                        },
                      ),
                      const Text('Available'),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quick category toggles (Smokes / Drinks) – checkbox + color only
                  Row(
                    children: [
                      Tooltip(
                        message: 'Smokes',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Smokes')?.toString(),
                              onChanged: (v) {
                                final smokesId = _categoryIdForName('Smokes');
                                if (smokesId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = smokesId;
                                  } else {
                                    selectedCategoryId = _getCategoryIdentifier(
                                        _categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Smokes'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SM',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Tooltip(
                        message: 'Drinks',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Drinks')?.toString(),
                              onChanged: (v) {
                                final drinksId = _categoryIdForName('Drinks');
                                if (drinksId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = drinksId;
                                  } else {
                                    selectedCategoryId = _getCategoryIdentifier(
                                        _categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Drinks'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'DR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Inventory Management Section
                  FutureBuilder<double>(
                    future: _getProductStock(product),
                    builder: (context, snapshot) {
                      final currentStock = snapshot.data ?? 0.0;
                      final stockController = TextEditingController();
                      
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.inventory_2, size: 20, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Inventory Management',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Current Stock',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          currentStock.toStringAsFixed(2),
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: currentStock > 0 
                                                ? Colors.green[700] 
                                                : Colors.red[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (currentStock > 0)
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green[700],
                                        size: 24,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: stockController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'Quantity to Add',
                                        hintText: 'Enter quantity',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final quantityText = stockController.text.trim();
                                      if (quantityText.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Please enter a quantity'),
                                          ),
                                        );
                                        return;
                                      }
                                      
                                      final quantity = double.tryParse(quantityText);
                                      if (quantity == null || quantity <= 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Please enter a valid quantity'),
                                          ),
                                        );
                                        return;
                                      }
                                      
                                      try {
                                        final dbProvider = Provider.of<UnifiedDatabaseProvider>(
                                          context,
                                          listen: false,
                                        );
                                        await dbProvider.init();
                                        
                                        final productId = kIsWeb ? product.documentId : product.id;
                                        if (productId == null) {
                                          throw Exception('Product ID is required');
                                        }
                                        
                                        // Ensure product is marked as purchasable
                                        if (!product.isPurchasable) {
                                          final now = DateTime.now().millisecondsSinceEpoch;
                                          await dbProvider.update(
                                            'products',
                                            values: {
                                              'is_purchasable': 1,
                                              'updated_at': now,
                                            },
                                            where: kIsWeb ? 'documentId = ?' : 'id = ?',
                                            whereArgs: [productId],
                                          );
                                        }
                                        
                                        // Create inventory ledger entry
                                        final auth = Provider.of<InaraAuthProvider>(context, listen: false);
                                        // createdBy must be int? for InventoryLedger
                                        // For Firestore (web), try to parse string user ID as int
                                        int? createdBy;
                                        if (auth.currentUserId != null) {
                                          if (kIsWeb) {
                                            // Firestore: try to parse string user ID as int
                                            createdBy = int.tryParse(auth.currentUserId!);
                                          } else {
                                            // SQLite: parse string user ID as int
                                            createdBy = int.tryParse(auth.currentUserId!);
                                          }
                                        }
                                        
                                        final ledgerEntry = InventoryLedger(
                                          productId: productId,
                                          productName: product.name,
                                          quantityIn: quantity,
                                          quantityOut: 0.0,
                                          unitPrice: product.cost ?? 0.0,
                                          transactionType: 'manual_adjustment',
                                          referenceType: 'manual',
                                          referenceId: null,
                                          notes: 'Manual stock addition from menu',
                                          createdBy: createdBy,
                                          createdAt: DateTime.now().millisecondsSinceEpoch,
                                        );
                                        
                                        final ledgerService = InventoryLedgerService();
                                        await ledgerService.addLedgerEntry(
                                          context: context,
                                          ledgerEntry: ledgerEntry,
                                        );
                                        
                                        // Refresh stock display
                                        setState(() {
                                          stockController.clear();
                                        });
                                        
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Added ${quantity.toStringAsFixed(2)} to stock',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        
                                        // Refresh the stock value
                                        setState(() {});
                                      } catch (e) {
                                        debugPrint('Error adding stock: $e');
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error: ${e.toString()}'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Stock'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Buttons
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        // NEW: delete menu item (admin only dialog)
                        onPressed: () => Navigator.pop(context, 'delete'),
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, 'save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == 'delete') {
      await _deleteMenuItem(product);
      return;
    }

    if (result == 'save' &&
        nameController.text.isNotEmpty &&
        priceController.text.isNotEmpty &&
        selectedCategoryId != null &&
        (kIsWeb ? product.documentId != null : product.id != null)) {
      try {
        final newName = nameController.text.trim();

        // Disallow duplicate menu item names (case-insensitive), excluding self.
        final normalizedNew = _normalizeNameKey(newName);
        final isDuplicate = _products.any((p) {
          final sameRecord = kIsWeb
              ? (p.documentId != null && p.documentId == product.documentId)
              : (p.id != null && p.id == product.id);
          if (sameRecord) return false;
          return _normalizeNameKey(p.name) == normalizedNew;
        });
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Menu item "$newName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        String? finalImageUrl = imageUrlController.text.trim().isEmpty
            ? null
            : imageUrlController.text.trim();

        // If image was uploaded, copy it to app directory and use local path
        if (selectedImageFile != null && !kIsWeb) {
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final imageDir = io.Directory('${appDir.path}/product_images');
            if (!await imageDir.exists()) {
              await imageDir.create(recursive: true);
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            final fileName =
                '${now}_${nameController.text.trim().replaceAll(' ', '_')}.jpg';
            final savedImage = await io.File(selectedImageFile!.path)
                .copy('${imageDir.path}/$fileName');
            finalImageUrl = savedImage.path;
          } catch (e) {
            debugPrint('Error saving image: $e');
          }
        }

        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);

        // Auto-assign image by name if none provided.
        finalImageUrl ??= _defaultMenuImageForName(newName);

        await dbProvider.update(
          'products',
          values: {
            'category_id': selectedCategoryId,
            'name': newName,
            'description': descController.text.trim().isEmpty
                ? null
                : descController.text.trim(),
            'price': double.parse(priceController.text),
            'image_url': finalImageUrl,
            'is_veg': isVeg ? 1 : 0,
            'is_active': isActive ? 1 : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [kIsWeb ? product.documentId : product.id],
        );
        await _loadData(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product updated'),
              backgroundColor: AppTheme.successColor,
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
