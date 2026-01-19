import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/inventory_ledger_service.dart';
import '../../models/product.dart';
import '../../models/inventory_ledger_model.dart';
import '../../utils/theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// FIXED: Inventory Screen now uses ledger-based stock calculation
/// Stock is NEVER stored directly - always calculated from inventory_ledger
class InventoryScreen extends StatefulWidget {
  final bool hideAppBar;
  const InventoryScreen({super.key, this.hideAppBar = false});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final InventoryLedgerService _ledgerService = InventoryLedgerService();
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _lowStockItems = [];
  bool _isLoading = true;
  String _viewMode = 'inventory'; // 'inventory' or 'movement' or 'report'

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  /// FIXED: Load inventory using ledger-based stock calculation
  /// Stock is calculated from inventory_ledger, not from inventory table
  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Inventory should be separate from Menu/Orders.
      // We only show *purchasable* items here (raw materials / stock items),
      // not sellable menu items.
      List<Map<String, dynamic>> productMaps;

      if (kIsWeb) {
        // Firestore: use a simple filter (server-side), then sort in memory
        productMaps = await dbProvider.query(
          'products',
          where: 'is_purchasable = ?',
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
          where: 'is_purchasable = ?',
          whereArgs: [1],
          orderBy: 'name ASC',
        );
      }

      final products = productMaps.map((map) => Product.fromMap(map)).toList();

      // FIXED: Calculate stock from ledger for each product
      final List<Map<String, dynamic>> inventoryList = [];
      final List<Map<String, dynamic>> lowStockList = [];

      // PERF: Batch-calc stock (avoids N sequential queries on web)
      final productIds = products
          .map((p) => kIsWeb ? p.documentId : p.id)
          .where((id) => id != null)
          .toList()
          .cast<dynamic>();
      final stockMap = await _ledgerService.getCurrentStockBatch(
        context: context,
        productIds: productIds,
      );

      for (final product in products) {
        final productId = kIsWeb ? product.documentId : product.id;
        if (productId == null) continue;

        final currentStock = stockMap[productId] ?? 0.0;

        // Get min stock level (default to 0 if not set)
        final minStockLevel = 0.0; // Can be configured per product later

        final isLowStock = currentStock <= minStockLevel;

        final inventoryItem = {
          'product_id': productId,
          'product_name': product.name,
          'quantity':
              currentStock, // FIXED: Stock from ledger, not inventory table
          'min_stock_level': minStockLevel,
          'is_low_stock': isLowStock ? 1 : 0,
          'selling_price': product.price,
          'purchase_price': product.cost,
          'category_name': null, // Can be added if needed
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

      _inventory = inventoryList;
      _lowStockItems = lowStockList;
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
                              _inventory = _lowStockItems;
                            });
                          },
                          child: const Text('View'),
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
                                            '${item['category_name']} • ${item['unit']}'),
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
                                    onTap: () =>
                                        _showAdjustInventoryDialog(item),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAdjustInventoryDialog(Map<String, dynamic> item) async {
    final quantityController =
        TextEditingController(text: item['quantity'].toString());
    final minLevelController =
        TextEditingController(text: item['min_stock_level'].toString());
    String transactionType = 'adjustment';
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        final newQuantity = double.tryParse(quantityController.text) ?? 0;

        if (newQuantity < 0) {
          throw Exception('Stock cannot be negative');
        }

        // FIXED: Use ledger service to create adjustment entry (not direct update)
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        await dbProvider.init();

        final productId = item['product_id'];
        final productName = item['product_name'] as String;

        // FIXED: Get current stock from ledger (not from inventory table)
        final currentStock = await _ledgerService.getCurrentStock(
          context: context,
          productId: productId,
        );

        final difference = newQuantity - currentStock;

        if (difference == 0) {
          // No change needed
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No stock change needed')),
            );
          }
          return;
        }

        // FIXED: Create ledger entry for adjustment instead of direct update
        final now = DateTime.now().millisecondsSinceEpoch;
        final createdBy = authProvider.currentUserId != null
            ? int.tryParse(authProvider.currentUserId!)
            : null;

        // Create adjustment ledger entry
        if (difference > 0) {
          // Stock increase
          await _ledgerService.addLedgerEntry(
            context: context,
            ledgerEntry: InventoryLedger(
              productId: productId,
              productName: productName,
              transactionType: transactionType,
              quantityIn: difference,
              quantityOut: 0.0,
              unitPrice: 0.0, // Adjustment doesn't have a cost
              referenceType: 'adjustment',
              referenceId: null,
              notes: notesController.text.trim().isEmpty
                  ? 'Manual stock adjustment'
                  : notesController.text.trim(),
              createdBy: createdBy,
              createdAt: now,
            ),
          );
        } else {
          // Stock decrease
          await _ledgerService.addLedgerEntry(
            context: context,
            ledgerEntry: InventoryLedger(
              productId: productId,
              productName: productName,
              transactionType: transactionType,
              quantityIn: 0.0,
              quantityOut: difference.abs(),
              unitPrice: 0.0, // Adjustment doesn't have a cost
              referenceType: 'adjustment',
              referenceId: null,
              notes: notesController.text.trim().isEmpty
                  ? 'Manual stock adjustment'
                  : notesController.text.trim(),
              createdBy: createdBy,
              createdAt: now,
            ),
          );
        }

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
