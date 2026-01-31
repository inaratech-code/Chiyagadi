import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../services/purchase_service.dart';
import '../../services/supplier_service.dart';
import '../../models/product.dart';
import '../../models/purchase_item_model.dart';
import '../../utils/theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'suppliers_screen.dart';

class PurchasesScreen extends StatefulWidget {
  final bool hideAppBar;
  final String? preSelectedSupplier;
  const PurchasesScreen(
      {super.key, this.hideAppBar = false, this.preSelectedSupplier});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final PurchaseService _purchaseService = PurchaseService();
  final SupplierService _supplierService = SupplierService();
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _purchasePayments = []; // Payment history
  bool _isLoading = false;
  bool _isCreatingPurchase = false; // Prevent duplicate submissions
  int _purchasesLimit = 50;
  bool _canLoadMore = false;

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPurchases());
    // If supplier is pre-selected, open add purchase dialog
    if (widget.preSelectedSupplier != null &&
        widget.preSelectedSupplier!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAddPurchaseDialog(preSelectedSupplier: widget.preSelectedSupplier);
      });
    }
  }

  Future<void> _loadPurchases() async {
    if (!mounted) return;
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final purchases = await dbProvider.query(
        'purchases',
        orderBy: 'created_at DESC',
        limit: _purchasesLimit,
      );
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _canLoadMore = purchases.length >= _purchasesLimit;
        });
      }
    } catch (e) {
      debugPrint('Error loading purchases: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading purchases: $e'),
            backgroundColor: Colors.red,
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
    final authProvider = Provider.of<InaraAuthProvider>(context);

    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Purchase Management'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.business),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SuppliersScreen(),
                      ),
                    ).then((_) => _loadPurchases());
                  },
                  tooltip: 'Suppliers / Parties',
                ),
                if (authProvider.isAdmin)
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddPurchaseDialog(),
                    tooltip: 'Add Purchase',
                  ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _purchases.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_bag,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No purchases found',
                          style: TextStyle(color: Colors.grey[600])),
                      if (authProvider.isAdmin) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showAddPurchaseDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Purchase'),
                        ),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary Cards
                    _buildSummarySection(),
                    // Purchases List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _purchases.length + (_canLoadMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_canLoadMore && index == _purchases.length) {
                            return Padding(
                              padding:
                                  const EdgeInsets.only(top: 8, bottom: 24),
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _purchasesLimit += 50;
                                  });
                                  _loadPurchases();
                                },
                                child: const Text('Load more'),
                              ),
                            );
                          }
                          final purchase = _purchases[index];
                          final date = DateTime.fromMillisecondsSinceEpoch(
                              (purchase['created_at'] as num).toInt());
                          final totalAmount =
                              (purchase['total_amount'] as num?)?.toDouble() ??
                                  0.0;
                          final paidAmount =
                              (purchase['paid_amount'] as num?)?.toDouble() ??
                                  0.0;
                          final outstandingAmount =
                              (purchase['outstanding_amount'] as num?)
                                      ?.toDouble() ??
                                  (totalAmount - paidAmount);
                          final hasOutstanding = outstandingAmount > 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            // Softer, logo-matching palette
                            color: hasOutstanding
                                ? AppTheme.warningColor.withOpacity(0.12)
                                : AppTheme.successColor.withOpacity(0.12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showPurchaseDetails(purchase),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isNarrow = constraints.maxWidth < 420;

                                    final right = Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          NumberFormat.currency(symbol: 'NPR ')
                                              .format(totalAmount),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                        ),
                                        if (paidAmount > 0)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Paid: ${NumberFormat.currency(symbol: 'NPR ').format(paidAmount)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        if (authProvider.isAdmin &&
                                            hasOutstanding) ...[
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            height: 32,
                                            child: ElevatedButton.icon(
                                              onPressed: () =>
                                                  _showPurchasePaymentDialog(
                                                      purchase),
                                              icon: const Icon(Icons.payment,
                                                  size: 16),
                                              label: const Text('Receive',
                                                  style:
                                                      TextStyle(fontSize: 12)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppTheme.logoPrimary,
                                                foregroundColor:
                                                    AppTheme.logoAccent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                minimumSize: const Size(0, 32),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    );

                                    final left = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Purchase #${purchase['purchase_number']}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${purchase['supplier_name']} • ${DateFormat('MMM dd, yyyy').format(date)}',
                                          style: TextStyle(
                                              color: Colors.grey[800]),
                                        ),
                                        if ((purchase['bill_number'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Bill: ${purchase['bill_number']}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[700]),
                                            ),
                                          ),
                                        if (hasOutstanding)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Outstanding: ${NumberFormat.currency(symbol: 'NPR ').format(outstandingAmount)}',
                                              style: TextStyle(
                                                color: AppTheme.warningColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    );

                                    if (isNarrow) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: hasOutstanding
                                                    ? AppTheme.warningColor
                                                    : AppTheme.successColor,
                                                child: Icon(
                                                  hasOutstanding
                                                      ? Icons.pending
                                                      : Icons.check_circle,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(child: left),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: right,
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: hasOutstanding
                                              ? AppTheme.warningColor
                                              : AppTheme.successColor,
                                          child: Icon(
                                            hasOutstanding
                                                ? Icons.pending
                                                : Icons.check_circle,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(child: left),
                                        const SizedBox(width: 12),
                                        right,
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: authProvider.isAdmin && _purchases.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddPurchaseDialog(),
              backgroundColor: AppTheme.logoPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Add Purchase'),
            )
          : null,
    );
  }

  Future<void> _showAddPurchaseDialog({String? preSelectedSupplier}) async {
    final supplierController =
        TextEditingController(text: preSelectedSupplier ?? '');
    final billNumberController = TextEditingController();
    final notesController = TextEditingController();
    final List<Map<String, dynamic>> items = [];

    // IMPORTANT: Purchase items should be manually entered and MUST NOT be linked with Menu items.
    // We intentionally do NOT load products into a dropdown here.
    final dbProvider =
        Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    await dbProvider.init();

    final List<Product> products = [];

    // Load all suppliers for autocomplete
    final suppliers = await _supplierService.getAllSuppliers(
      context: context,
      activeOnly: true,
    );
    final supplierNames = suppliers.map((s) => s.name).toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Purchase'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // UPDATED: Autocomplete for supplier name with dropdown
                Autocomplete<String>(
                  initialValue: preSelectedSupplier != null
                      ? TextEditingValue(text: preSelectedSupplier)
                      : null,
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return supplierNames;
                    }
                    return supplierNames.where((String option) {
                      return option
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    supplierController.text = selection;
                  },
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController textEditingController,
                    FocusNode focusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    // Initialize with pre-selected supplier or existing controller value
                    if (preSelectedSupplier != null &&
                        textEditingController.text.isEmpty) {
                      textEditingController.text = preSelectedSupplier;
                      supplierController.text = preSelectedSupplier;
                    }
                    // Sync changes from autocomplete controller to main controller
                    textEditingController.addListener(() {
                      if (supplierController.text !=
                          textEditingController.text) {
                        supplierController.text = textEditingController.text;
                      }
                    });
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration:
                          const InputDecoration(labelText: 'Supplier Name *'),
                      autofocus: true,
                      onSubmitted: (String value) {
                        onFieldSubmitted();
                      },
                    );
                  },
                  optionsViewBuilder: (
                    BuildContext context,
                    AutocompleteOnSelected<String> onSelected,
                    Iterable<String> options,
                  ) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width:
                              250, // UPDATED: Fixed smaller width for dropdown
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 200,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () {
                                    onSelected(option);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      option,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: billNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Bill Number (optional)',
                    hintText: 'Supplier invoice / bill no.',
                  ),
                ),
                TextField(
                  controller: notesController,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('Purchase Items',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final displayName =
                      (item['product_name'] as String?)?.trim().isNotEmpty ==
                              true
                          ? (item['product_name'] as String).trim()
                          : 'Item';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(displayName),
                      subtitle: Text(
                          'Qty: ${item['quantity']}, Cost: ${NumberFormat.currency(symbol: 'NPR ').format(item['unit_price'])}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setDialogState(() => items.removeAt(index));
                        },
                      ),
                    ),
                  );
                }),
                ElevatedButton.icon(
                  onPressed: () => _showAddPurchaseItemDialog(
                      context, setDialogState, items, products),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
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
              onPressed: (items.isEmpty ||
                      supplierController.text.isEmpty ||
                      _isCreatingPurchase)
                  ? null
                  : () => Navigator.pop(context, true),
              child: _isCreatingPurchase
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true &&
        supplierController.text.isNotEmpty &&
        items.isNotEmpty) {
      // Prevent duplicate submissions
      if (_isCreatingPurchase) return;

      setState(() => _isCreatingPurchase = true);

      try {
        // Ensure supplier exists and link purchase to supplier_id (connect suppliers ↔ purchases)
        final supplierName = supplierController.text.trim();
        final supplierId = await _supplierService.getOrCreateSupplierIdByName(
          context: context,
          supplierName: supplierName,
        );

        // Convert items to PurchaseItem models
        final purchaseItems = <PurchaseItem>[];
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);

        for (final item in items) {
          final isManual = item['is_manual'] == true;
          dynamic productId = item['product_id'];
          String productName = item['product_name'] ?? 'Unknown';
          final unit = (item['unit'] as String?)?.trim().isNotEmpty == true
              ? (item['unit'] as String).trim()
              : 'pcs';

          // For manual entries, try to find or create the product
          if (isManual && productId == null) {
            productName = item['product_name'] as String;
            // UPDATED: First try to find ANY existing product by name (case-insensitive)
            // This ensures purchases add inventory to the same product used in orders
            Product? matchedProduct;

            if (kIsWeb) {
              // Firestore: Get all products and match in-memory (case-insensitive)
              final allProducts = await dbProvider.query('products');
              final normalizedName = productName.trim().toLowerCase();
              for (final prodMap in allProducts) {
                final prod = Product.fromMap(prodMap);
                if (prod.name.trim().toLowerCase() == normalizedName) {
                  matchedProduct = prod;
                  break;
                }
              }
            } else {
              // SQLite: Try exact match first, then case-insensitive
              var allProducts = await dbProvider.query(
                'products',
                where: 'name = ?',
                whereArgs: [productName],
              );

              if (allProducts.isEmpty) {
                // Try case-insensitive match
                allProducts = await dbProvider.query('products');
                final normalizedName = productName.trim().toLowerCase();
                for (final prodMap in allProducts) {
                  final prod = Product.fromMap(prodMap);
                  if (prod.name.trim().toLowerCase() == normalizedName) {
                    allProducts = [prodMap];
                    break;
                  }
                }
              }

              if (allProducts.isNotEmpty) {
                matchedProduct = Product.fromMap(allProducts.first);
              }
            }

            if (matchedProduct != null) {
              // Use existing product (whether sellable or not) to ensure inventory matches
              productId =
                  kIsWeb ? matchedProduct.documentId : matchedProduct.id;
              productName = matchedProduct.name;

              debugPrint(
                  'Purchase: Matched existing product "$productName" (ID: $productId) for purchase item');

              // UPDATED: If product exists but isn't purchasable, mark it as purchasable
              if (!matchedProduct.isPurchasable) {
                final now = DateTime.now().millisecondsSinceEpoch;
                await dbProvider.update(
                  'products',
                  values: {
                    'is_purchasable': 1,
                    'cost': (item['unit_price'] as num).toDouble(),
                    'updated_at': now,
                  },
                  where: kIsWeb ? 'documentId = ?' : 'id = ?',
                  whereArgs: [productId],
                );
                debugPrint(
                    'Purchase: Updated product "$productName" to be purchasable');
              }
            } else {
              debugPrint(
                  'Purchase: No existing product found for "$productName", creating new product');
              // Create a new product that can be both purchased and sold
              // UPDATED: Check if this might be a menu item by looking for similar names
              final now = DateTime.now().millisecondsSinceEpoch;

              // Try to find a category (default to first category or 0)
              final categories = await dbProvider.query('categories', limit: 1);
              final categoryId = categories.isNotEmpty
                  ? (kIsWeb ? categories.first['id'] : categories.first['id'])
                  : 0;

              productId = await dbProvider.insert('products', {
                'category_id': categoryId,
                'name': productName,
                'description': 'Purchase item',
                'price': 0, // Will be set when sold
                'cost': (item['unit_price'] as num).toDouble(),
                'image_url': null,
                'is_veg': 1,
                'is_active': 1,
                'is_purchasable': 1, // Can be purchased
                'is_sellable':
                    1, // UPDATED: Can also be sold (inventory items like drinks)
                'created_at': now,
                'updated_at': now,
              });
            }
          } else if (!isManual && productId != null) {
            // Find product from list
            try {
              final product = products.firstWhere(
                (p) => (kIsWeb ? p.documentId : p.id) == productId,
              );
              productName = product.name;
            } catch (e) {
              // Product not found in list, use stored name
              debugPrint('Product not found in list, using stored name');
            }
          }

          purchaseItems.add(PurchaseItem(
            purchaseId: null, // Will be set by service
            productId: productId,
            productName: productName,
            unit: unit,
            quantity: (item['quantity'] as num).toDouble(),
            unitPrice: (item['unit_price'] as num).toDouble(),
            totalPrice: (item['quantity'] as num).toDouble() *
                (item['unit_price'] as num).toDouble(),
            notes: null,
          ));
        }

        // Use PurchaseService to create purchase with ledger entries
        await _purchaseService.createPurchase(
          context: context,
          supplierId: supplierId,
          supplierName: supplierName,
          billNumber: billNumberController.text.trim().isEmpty
              ? null
              : billNumberController.text.trim(),
          items: purchaseItems,
          discountAmount: null,
          taxAmount: null,
          notes: notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
        );

        await _loadPurchases(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Purchase added successfully. Stock updated via ledger.'),
              backgroundColor: const Color(0xFF00B894),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error creating purchase: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating purchase: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isCreatingPurchase = false);
        }
      }
    }
  }

  Future<void> _showAddPurchaseItemDialog(
    BuildContext context,
    StateSetter setDialogState,
    List<Map<String, dynamic>> items,
    List<Product> products,
  ) async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController();
    String selectedUnit = 'pcs';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setItemState) => AlertDialog(
          title: const Text('Add Purchase Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    hintText: 'e.g., Flour, Sugar, Tea Leaves',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  onChanged: (_) => setItemState(() {}),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit *',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'gm', child: Text('gm')),
                    DropdownMenuItem(value: 'ltr', child: Text('ltr')),
                    DropdownMenuItem(value: 'ml', child: Text('ml')),
                    DropdownMenuItem(value: 'pack', child: Text('pack')),
                  ],
                  onChanged: (value) {
                    setItemState(() {
                      selectedUnit = value ?? 'pcs';
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: quantityController,
                  decoration: const InputDecoration(labelText: 'Quantity *'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setItemState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  decoration:
                      const InputDecoration(labelText: 'Unit Price (Cost) *'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setItemState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: nameController.text.trim().isEmpty ||
                      quantityController.text.isEmpty ||
                      priceController.text.isEmpty
                  ? null
                  : () {
                      final quantity =
                          double.tryParse(quantityController.text) ?? 0;
                      final price = double.tryParse(priceController.text) ?? 0;
                      if (quantity > 0 && price >= 0) {
                        setDialogState(() {
                          // Manual entry: create a temporary product entry
                          // The product will be created on-the-fly or referenced by name
                          items.add({
                            'product_id':
                                null, // Will be handled during purchase creation
                            'product_name': nameController.text.trim(),
                            'unit': selectedUnit,
                            'quantity': quantity,
                            'unit_price': price,
                            'is_manual': true,
                          });
                        });
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    double totalPurchases = 0.0;
    double totalPaid = 0.0;
    double totalOutstanding = 0.0;

    for (var purchase in _purchases) {
      final total = (purchase['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paid = (purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final outstanding =
          (purchase['outstanding_amount'] as num?)?.toDouble() ??
              (total - paid);

      totalPurchases += total;
      totalPaid += paid;
      totalOutstanding += outstanding;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Purchase Summary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Total Purchases',
                  totalPurchases,
                  AppTheme.logoPrimary, // Logo golden
                  Icons.shopping_bag,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryCard(
                  'Total Paid',
                  totalPaid,
                  AppTheme.successColor, // Green
                  Icons.payment,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Outstanding',
                  totalOutstanding,
                  AppTheme.warningColor, // Logo secondary
                  Icons.account_balance_wallet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
      String label, double amount, Color color, IconData icon) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              NumberFormat.currency(symbol: 'NPR ').format(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                // User request: amounts should be dark for readability
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPurchasePayments(dynamic purchaseId) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      _purchasePayments = await dbProvider.query(
        'purchase_payments',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      debugPrint('Error loading purchase payments: $e');
      _purchasePayments = [];
    }
  }

  Future<void> _showPurchaseDetails(Map<String, dynamic> purchase) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      // Handle both int (SQLite) and String (Firestore) IDs
      final purchaseId = purchase['id'] ?? purchase['documentId'];
      if (purchaseId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid purchase ID')),
          );
        }
        return;
      }

      final items = await dbProvider.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
      );

      await _loadPurchasePayments(purchaseId);

      if (!mounted) return;

      final totalAmount = (purchase['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final outstandingAmount =
          (purchase['outstanding_amount'] as num?)?.toDouble() ??
              (totalAmount - paidAmount);
      final hasOutstanding = outstandingAmount > 0;

      final authProvider =
          Provider.of<InaraAuthProvider>(context, listen: false);

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Purchase #${purchase['purchase_number']}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Supplier: ${purchase['supplier_name']}'),
                if ((purchase['bill_number'] as String?)?.trim().isNotEmpty ==
                    true)
                  Text('Bill: ${purchase['bill_number']}'),
                Text(
                    'Date: ${DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch((purchase['created_at'] as num).toInt()))}'),
                if (purchase['notes'] != null)
                  Text('Notes: ${purchase['notes']}'),
                const Divider(),
                // Payment Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasOutstanding
                        ? const Color(0xFFFF6B6B).withOpacity(0.1)
                        : const Color(0xFF00B894).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasOutstanding
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFF00B894),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            NumberFormat.currency(symbol: 'NPR ')
                                .format(totalAmount),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (paidAmount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Paid:',
                                style: TextStyle(color: Color(0xFF00B894))),
                            Text(
                              NumberFormat.currency(symbol: 'NPR ')
                                  .format(paidAmount),
                              style: const TextStyle(
                                  color: Color(0xFF00B894),
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                      if (hasOutstanding) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Outstanding:',
                                style: TextStyle(
                                    color: Color(0xFFFF6B6B),
                                    fontWeight: FontWeight.bold)),
                            Text(
                              NumberFormat.currency(symbol: 'NPR ')
                                  .format(outstandingAmount),
                              style: const TextStyle(
                                  color: Color(0xFFFF6B6B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(),
                const Text('Items:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              'Product ${item['product_id']} x ${item['quantity']}'),
                          Text(NumberFormat.currency(symbol: 'NPR ')
                              .format(item['total_price'])),
                        ],
                      ),
                    )),
                if (_purchasePayments.isNotEmpty) ...[
                  const Divider(),
                  const Text('Payment History:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._purchasePayments.map((payment) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(DateFormat('MMM dd, yyyy').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                        (payment['created_at'] as num)
                                            .toInt()))),
                                if (payment['payment_method'] != null)
                                  Text(
                                    payment['payment_method'] as String,
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                            Text(
                              NumberFormat.currency(symbol: 'NPR ')
                                  .format(payment['amount']),
                              style: const TextStyle(
                                  color: Color(0xFF00B894),
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (hasOutstanding && authProvider.isAdmin)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showPurchasePaymentDialog(purchase);
                },
                icon: const Icon(Icons.payment),
                label: const Text('Make Payment'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B894)),
              ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error showing purchase details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showPurchasePaymentDialog(Map<String, dynamic> purchase) async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final paymentMethodNotifier = ValueNotifier<String>('cash');
    final isPartialPaymentNotifier = ValueNotifier<bool>(false);

    final totalAmount = (purchase['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final outstandingAmount =
        (purchase['outstanding_amount'] as num?)?.toDouble() ??
            (totalAmount - paidAmount);

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Make Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Purchase #${purchase['purchase_number']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Outstanding Amount:'),
                      Text(
                        NumberFormat.currency(symbol: 'NPR ')
                            .format(outstandingAmount),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFFFF6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'Payment Amount (NPR) *',
                    hintText: 'Enter amount to pay',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.currency_rupee),
                    suffixText: 'NPR',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onChanged: (value) {
                    final amount = double.tryParse(value) ?? 0;
                    setDialogState(() {
                      isPartialPaymentNotifier.value =
                          amount > 0 && amount < outstandingAmount;
                    });
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: isPartialPaymentNotifier,
                  builder: (context, isPartial, _) {
                    if (!isPartial || amountController.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Partial payment. Remaining: ${NumberFormat.currency(symbol: 'NPR ').format(outstandingAmount - (double.tryParse(amountController.text) ?? 0))}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.blue[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: paymentMethodNotifier,
                  builder: (context, paymentMethod, _) =>
                      DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payment),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(
                          value: 'bank_transfer', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      paymentMethodNotifier.value = value ?? 'cash';
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
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
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                if (amount > outstandingAmount) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Amount cannot exceed outstanding balance of ${NumberFormat.currency(symbol: 'NPR ').format(outstandingAmount)}')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'amount': amount,
                  'paymentMethod': paymentMethodNotifier.value,
                  'notes': notesController.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B894)),
              child: const Text('Make Payment'),
            ),
          ],
        ),
      ),
    );

    if (result != null &&
        result['amount'] != null &&
        (result['amount'] as double) > 0) {
      final paymentMethod = result['paymentMethod'] as String? ?? 'cash';
      final notes = result['notes'] as String? ?? '';
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final authProvider =
            Provider.of<InaraAuthProvider>(context, listen: false);
        final purchaseId = kIsWeb
            ? (purchase['documentId'] ?? purchase['id'])
            : purchase['id'];
        if (purchaseId == null) return;

        final amount = result['amount'] as double;
        final now = DateTime.now().millisecondsSinceEpoch;
        final currentPaid = paidAmount;
        final newPaid = currentPaid + amount;
        final newOutstanding =
            (totalAmount - newPaid).clamp(0.0, double.infinity);
        final newPaymentStatus =
            newOutstanding <= 0 ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');

        // Create payment record
        await dbProvider.insert('purchase_payments', {
          'purchase_id': purchaseId,
          'amount': amount,
          'payment_method': paymentMethod,
          'notes': notes.isEmpty
              ? (newOutstanding > 0 ? 'Partial payment' : null)
              : notes,
          'created_by': authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
          'created_at': now,
          'synced': 0,
        });

        // Update purchase payment status
        await dbProvider.update(
          'purchases',
          values: {
            'paid_amount': newPaid,
            'outstanding_amount': newOutstanding,
            'payment_status': newPaymentStatus,
            'updated_at': now,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [purchaseId],
        );

        await _loadPurchases();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newOutstanding > 0
                    ? 'Partial payment of ${NumberFormat.currency(symbol: 'NPR ').format(amount)} received. Remaining: ${NumberFormat.currency(symbol: 'NPR ').format(newOutstanding)}'
                    : 'Payment received successfully',
              ),
              backgroundColor: const Color(0xFF00B894),
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
