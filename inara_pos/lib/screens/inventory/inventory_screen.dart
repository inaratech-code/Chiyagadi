import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../models/product.dart';
import '../../models/inventory_ledger_model.dart';
import '../../utils/theme.dart';
import '../../utils/inventory_category_helper.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../purchases/purchases_screen.dart';

/// FIXED: Inventory Screen now uses ledger-based stock calculation
/// Stock is NEVER stored directly - always calculated from inventory_ledger
class InventoryScreen extends StatefulWidget {
  final bool hideAppBar;
  const InventoryScreen({super.key, this.hideAppBar = false});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  // UPDATED: Keep the full list and apply filters without losing data.
  List<Map<String, dynamic>> _allInventory = [];
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoading = false;
  String _viewMode = 'inventory'; // 'inventory' or 'movement' or 'report'

  // NEW: Inventory category filter (requested)
  String _categoryFilter = 'all'; // all | cigarettes | cold_drinks | cookies
  bool _showLowStockOnly = false;

  // NEW: Simple categorization (no schema change; works offline + web)
  String _categoryForName(String name) {
    final n = name.trim().toLowerCase();
    // Cigarettes
    if (n.contains('marlboro') ||
        n.contains('gold flake') ||
        n.contains('red') ||
        n.contains('white') ||
        n.contains('555') ||
        n.contains('cigarette')) {
      return 'cigarettes';
    }
    // Cold Drinks
    if (n.contains('cold drink') ||
        n.contains('coke') ||
        n.contains('pepsi') ||
        n.contains('dew') ||
        n.contains('soda') ||
        n.contains('water') ||
        n.contains('juice') ||
        n.contains('lassi')) {
      return 'cold_drinks';
    }
    // Cookies
    if (n.contains('cookie') ||
        n.contains('cookies') ||
        n.contains('biscuit')) {
      return 'cookies';
    }
    return 'other';
  }

  void _applyInventoryFilters() {
    List<Map<String, dynamic>> base = _allInventory;

    if (_showLowStockOnly) {
      base = _lowStockItems;
    }

    if (_categoryFilter != 'all') {
      base = base.where((i) {
        final name = (i['product_name'] ?? '').toString();
        return _categoryForName(name) == _categoryFilter;
      }).toList();
    }

    _inventory = base;
  }

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInventory());
  }

  /// FIXED: Load inventory using ledger-based stock calculation
  /// Stock is calculated from inventory_ledger, not from inventory table
  Future<void> _loadInventory() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // UPDATED: Only show products that track inventory (countable items: Food, Cold Drinks, Cigarettes)
      // These are sellable menu items that can be counted, not raw materials
      List<Map<String, dynamic>> productMaps;

      if (kIsWeb) {
        // Firestore: use a simple filter (server-side), then sort in memory
        productMaps = await dbProvider.query(
          'products',
          where: 'track_inventory = ?',
          whereArgs: [1],
        );

        // Sort in memory (Firestore orderBy with where requires index)
        productMaps.sort((a, b) {
          final nameA = (a['name'] as String? ?? '').toLowerCase();
          final nameB = (b['name'] as String? ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        });
      } else {
        // For SQLite: simple filter
        productMaps = await dbProvider.query(
          'products',
          where: 'track_inventory = ?',
          whereArgs: [1],
          orderBy: 'name ASC',
        );
      }

      final products = productMaps.map((map) => Product.fromMap(map)).toList();

      // UPDATED: Load categories to get category names
      final categoryMaps = await dbProvider.query('categories');
      final categoryMap = <dynamic, String>{};
      for (final cat in categoryMaps) {
        final catId = kIsWeb ? cat['id'] : cat['id'];
        final catName = cat['name'] as String? ?? 'Uncategorized';
        if (catId != null) {
          categoryMap[catId] = catName;
        }
      }

      // UPDATED: Use stockQuantity directly from products (not ledger-based)
      final List<Map<String, dynamic>> inventoryList = [];
      final List<Map<String, dynamic>> lowStockList = [];

      for (final product in products) {
        final productId = kIsWeb ? product.documentId : product.id;
        if (productId == null) continue;

        // Get stockQuantity directly from product map (Product model may not have it yet)
        final productMap = productMaps.firstWhere(
          (p) => (kIsWeb ? p['id'] : p['id']) == productId,
          orElse: () => <String, dynamic>{},
        );
        final currentStock =
            (productMap['stock_quantity'] as num?)?.toDouble() ?? 0.0;

        // UPDATED: Default min stock level (no manual editing; can be configured later)
        const minStockLevel = 5.0;

        final isLowStock = currentStock <= minStockLevel;

        // UPDATED: Get category name from category map
        final categoryName = categoryMap[product.categoryId] ?? 'Uncategorized';

        final inventoryItem = {
          'product_id': productId,
          'product_name': product.name,
          'quantity':
              currentStock, // FIXED: Stock from ledger, not inventory table
          'min_stock_level': minStockLevel,
          'is_low_stock': isLowStock ? 1 : 0,
          'selling_price': product.price,
          'purchase_price': product.cost,
          'category_name': categoryName, // UPDATED: Use actual category name
          'unit': 'pcs', // UPDATED: Default unit (can be enhanced later)
        };

        inventoryList.add(inventoryItem);

        if (isLowStock) {
          lowStockList.add(inventoryItem);
        }
      }

      // Sort by low stock first, then by name
      inventoryList.sort((a, b) {
        final isLowA = a['is_low_stock'] == 1;
        final isLowB = b['is_low_stock'] == 1;
        if (isLowA && !isLowB) return -1;
        if (!isLowA && isLowB) return 1;
        return (a['product_name'] as String)
            .compareTo(b['product_name'] as String);
      });

      _allInventory = inventoryList;
      _lowStockItems = lowStockList;
      _applyInventoryFilters();
    } catch (e) {
      debugPrint('Error loading inventory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading inventory: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Inventory Management'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadInventory,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'inventory_fab',
        onPressed: () {
          // Navigate to purchases screen to add inventory items
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const PurchasesScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Inventory'),
        tooltip: 'Add inventory items via purchase',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // View Mode Dropdown
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DropdownButton<String>(
                    value: _viewMode,
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.arrow_drop_down,
                        color: Theme.of(context).primaryColor),
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'inventory',
                        child: Text('Inventory List'),
                      ),
                      DropdownMenuItem(
                        value: 'movement',
                        child: Text('Stock Movement'),
                      ),
                      DropdownMenuItem(
                        value: 'report',
                        child: Text('Inventory Report'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _viewMode = value;
                          _loadInventory();
                        });
                      }
                    },
                  ),
                ),
                // Low Stock Alert Banner
                if (_lowStockItems.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.red[50],
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_lowStockItems.length} item(s) are low on stock!',
                            style: TextStyle(
                              color: Colors.red[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              // NEW: Low-stock view without manual stock editing
                              _showLowStockOnly = true;
                              _applyInventoryFilters();
                            });
                          },
                          child: const Text('View'),
                        ),
                      ],
                    ),
                  ),
                // NEW: Inventory categories (requested)
                if (_viewMode == 'inventory')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border(
                        bottom: BorderSide(
                            color: Colors.black.withOpacity(0.05), width: 1),
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _categoryFilter == 'all',
                          onSelected: (_) {
                            setState(() {
                              _categoryFilter = 'all';
                              _showLowStockOnly = false;
                              _applyInventoryFilters();
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Cigarettes'),
                          selected: _categoryFilter == 'cigarettes',
                          onSelected: (_) {
                            setState(() {
                              _categoryFilter = 'cigarettes';
                              _showLowStockOnly = false;
                              _applyInventoryFilters();
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Cold Drinks'),
                          selected: _categoryFilter == 'cold_drinks',
                          onSelected: (_) {
                            setState(() {
                              _categoryFilter = 'cold_drinks';
                              _showLowStockOnly = false;
                              _applyInventoryFilters();
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Cookies'),
                          selected: _categoryFilter == 'cookies',
                          onSelected: (_) {
                            setState(() {
                              _categoryFilter = 'cookies';
                              _showLowStockOnly = false;
                              _applyInventoryFilters();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                // Inventory List
                Expanded(
                  child: _inventory.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No inventory found',
                                  style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : _viewMode == 'movement'
                          ? _buildStockMovementView()
                          : ListView.builder(
                              cacheExtent: 400,
                              padding: const EdgeInsets.all(16),
                              itemCount: _inventory.length,
                              itemBuilder: (context, index) {
                                final item = _inventory[index];
                                final quantity =
                                    (item['quantity'] as num).toDouble();
                                final minLevel =
                                    (item['min_stock_level'] as num).toDouble();
                                final isLowStock = quantity <= minLevel;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: isLowStock ? Colors.red[50] : null,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isLowStock
                                          ? Colors.red
                                          : Colors.green,
                                      child: Text(
                                        item['product_name']
                                            .toString()
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    title: Text(item['product_name'] as String),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${item['category_name'] ?? 'Uncategorized'} • ${item['unit'] ?? 'pcs'}'),
                                        if (_viewMode == 'report' &&
                                            item['purchase_price'] != null)
                                          Text(
                                            'Cost: ${NumberFormat.currency(symbol: 'NPR ').format(item['purchase_price'])} | '
                                            'Sell: ${NumberFormat.currency(symbol: 'NPR ').format(item['selling_price'])}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600]),
                                          ),
                                        if (_viewMode == 'report' &&
                                            item['profit_margin_percent'] !=
                                                null)
                                          Text(
                                            'Margin: ${(item['profit_margin_percent'] as num).toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  (item['profit_margin_percent']
                                                                  as num)
                                                              .toDouble() >
                                                          0
                                                      ? Colors.green
                                                      : Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${quantity.toStringAsFixed(1)} ${item['unit']}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isLowStock
                                                ? Colors.red
                                                : Colors.green,
                                          ),
                                        ),
                                        if (isLowStock)
                                          const Text(
                                            'Low Stock!',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                    // ENABLED: Manual stock editing is now allowed
                                    onTap: () {
                                      _showAdjustInventoryDialog(item);
                                    },
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }

  // ignore: unused_element
  Future<void> _showAdjustInventoryDialog(Map<String, dynamic> item) async {
    // NOTE: Manual adjustments are intentionally disabled in UI (see onTap above).
    // Kept for future migration tooling, but should remain inaccessible for end-users.
    final quantityController =
        TextEditingController(text: item['quantity'].toString());
    final minLevelController =
        TextEditingController(text: item['min_stock_level'].toString());
    String transactionType = 'adjustment';
    final notesController = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Adjust Inventory: ${item['product_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantityController,
                  decoration:
                      const InputDecoration(labelText: 'New Quantity *'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: minLevelController,
                  decoration:
                      const InputDecoration(labelText: 'Min Stock Level *'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                DropdownButtonFormField<String>(
                  value: transactionType,
                  decoration:
                      const InputDecoration(labelText: 'Transaction Type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'adjustment', child: Text('Manual Adjustment')),
                    DropdownMenuItem(value: 'in', child: Text('Stock In')),
                    DropdownMenuItem(value: 'out', child: Text('Stock Out')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => transactionType = value!);
                  },
                ),
                TextField(
                  controller: notesController,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)'),
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
            TextButton(
              onPressed: () => Navigator.pop(context, 'delete'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Delete Stock'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'update'),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result == 'delete') {
      // Delete stock - set to 0
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await dbProvider.init();

        final productId = item['product_id'];

        // Validate that this product's category allows inventory tracking
        await validateInventoryAllowed(
          dbProvider: dbProvider,
          productId: productId,
        );

        // Get current stockQuantity directly from product
        final productData = await dbProvider.query(
          'products',
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [productId],
        );

        if (productData.isEmpty) {
          throw Exception('Product not found');
        }

        final currentStock =
            (productData.first['stock_quantity'] as num?)?.toDouble() ?? 0.0;

        if (currentStock <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Stock is already zero')),
            );
          }
          return;
        }

        // UPDATED: Update stockQuantity directly to 0 (not via ledger)
        final now = DateTime.now().millisecondsSinceEpoch;

        await dbProvider.update(
          'products',
          values: {
            'stock_quantity': 0.0,
            'updated_at': now,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [productId],
        );

        await _loadInventory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Stock deleted successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting stock: $e')),
          );
        }
      }
      return;
    }

    if (result == 'update') {
      try {
        final newQuantity = double.tryParse(quantityController.text) ?? 0;

        if (newQuantity < 0) {
          throw Exception('Stock cannot be negative');
        }

        // UPDATED: Validate category allows inventory tracking
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await dbProvider.init();

        final productId = item['product_id'];

        // Validate that this product's category allows inventory tracking
        await validateInventoryAllowed(
          dbProvider: dbProvider,
          productId: productId,
        );

        // Get current stockQuantity directly from product
        final productData = await dbProvider.query(
          'products',
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [productId],
        );

        if (productData.isEmpty) {
          throw Exception('Product not found');
        }

        final currentStock =
            (productData.first['stock_quantity'] as num?)?.toDouble() ?? 0.0;

        if (newQuantity == currentStock) {
          // No change needed
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No stock change needed')),
            );
          }
          return;
        }

        // UPDATED: Update stockQuantity directly (not via ledger)
        final now = DateTime.now().millisecondsSinceEpoch;

        await dbProvider.update(
          'products',
          values: {
            'stock_quantity': newQuantity,
            'updated_at': now,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [productId],
        );

        // Note: Min stock level can be stored in products table or a separate settings table
        // For now, we'll skip updating min_stock_level as it's not critical

        await _loadInventory(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: const Text('Inventory updated successfully'),
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

  Widget _buildStockMovementView() {
    // FIXED: Use ledger service to get stock movement history
    return FutureBuilder<List<InventoryLedger>>(
      future: _getStockMovementHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final movements = snapshot.data ?? [];

        if (movements.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No stock movements found',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }

        return ListView.builder(
          cacheExtent: 400,
          padding: const EdgeInsets.all(16),
          itemCount: movements.length,
          itemBuilder: (context, index) {
            final movement = movements[index];
            final date =
                DateTime.fromMillisecondsSinceEpoch(movement.createdAt);
            final isIn = movement.quantityIn > 0;
            final quantity = isIn ? movement.quantityIn : movement.quantityOut;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isIn ? Colors.green : Colors.red,
                  child: Icon(
                    isIn ? Icons.arrow_downward : Icons.arrow_upward,
                    color: Colors.white,
                  ),
                ),
                title: Text(movement.productName ?? 'Unknown Product'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${movement.transactionType} • ${DateFormat('MMM dd, yyyy HH:mm').format(date)}'),
                    if (movement.notes != null && movement.notes!.isNotEmpty)
                      Text(movement.notes!,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isIn ? '+' : '-'}${quantity.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isIn ? Colors.green : Colors.red,
                      ),
                    ),
                    if (movement.unitPrice > 0)
                      Text(
                        NumberFormat.currency(symbol: 'NPR ')
                            .format(movement.unitPrice),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// FIXED: Get stock movement history from ledger
  Future<List<InventoryLedger>> _getStockMovementHistory() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Get all ledger entries, ordered by most recent
      final entries = await dbProvider.query(
        'inventory_ledger',
        orderBy: 'created_at DESC',
        limit: 100,
      );

      return entries.map((e) => InventoryLedger.fromMap(e)).toList();
    } catch (e) {
      debugPrint('Error getting stock movement history: $e');
      return [];
    }
  }
}
