import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../providers/unified_database_provider.dart';
import '../../services/order_service.dart';
import '../../services/printer_service.dart';
import '../../utils/theme.dart';
import 'pos_cart_widget.dart';
import 'pos_product_grid.dart';
import 'pos_payment_dialog.dart';

class POSScreen extends StatefulWidget {
  const POSScreen({super.key});

  @override
  State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final OrderService _orderService = OrderService();
  final PrinterService _printerService = PrinterService();

  Order? _currentOrder;
  String _orderType = 'dine_in';
  int? _selectedTableId;
  bool _isAddingItem = false;
  List<OrderItem> _optimisticItems = [];
  Order? _optimisticOrder;
  final List<Product> _pendingPersist = [];

  @override
  void initState() {
    super.initState();
    _loadPendingOrder();
  }

  Future<void> _loadPendingOrder() async {
    setState(() {
      _currentOrder = null;
    });
  }

  void _addProductToCart(Product product) {
    if (_isAddingItem) return;

    final baseOrder = _optimisticOrder ?? _currentOrder;
    final baseSub = baseOrder?.subtotal ?? 0;
    final baseDiscount = baseOrder?.discountAmount ?? 0;
    final baseDiscountPct = baseOrder?.discountPercent ?? 0;
    final price = product.price;
    final newSub = baseSub + price;
    final newDiscount = newSub * (baseDiscountPct / 100);
    final newTotal = newSub - newDiscount;

    final tempOrderId = baseOrder != null
        ? (kIsWeb ? baseOrder.documentId : baseOrder.id)
        : null;
    final optItem = OrderItem(
      id: null,
      orderId: tempOrderId,
      productId: kIsWeb ? product.documentId : product.id,
      quantity: 1,
      unitPrice: price,
      totalPrice: price,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      product: product,
    );

    Order? optOrder;
    if (baseOrder != null) {
      optOrder = baseOrder.copyWith(
        subtotal: newSub,
        discountAmount: newDiscount,
        totalAmount: newTotal,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      optOrder = Order(
        orderNumber: '...',
        orderType: _orderType,
        tableId: _selectedTableId,
        subtotal: newSub,
        discountAmount: newDiscount,
        discountPercent: baseDiscountPct,
        totalAmount: newTotal,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    setState(() {
      _isAddingItem = true;
      _optimisticOrder = optOrder;
      _optimisticItems = [..._optimisticItems, optItem];
      _pendingPersist.add(product);
    });

    _processPendingPersist();
  }

  Future<void> _processPendingPersist() async {
    if (_pendingPersist.isEmpty) {
      if (mounted) setState(() => _isAddingItem = false);
      return;
    }
    final product = _pendingPersist.removeAt(0);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
      await dbProvider.init();

      dynamic orderId;
      if (_currentOrder == null) {
        orderId = await _orderService.createOrder(
          dbProvider: dbProvider,
          orderType: _orderType,
          tableId: _selectedTableId,
          createdBy: authProvider.currentUserId != null
              ? (kIsWeb
                  ? authProvider.currentUserId!
                  : int.tryParse(authProvider.currentUserId!))
              : null,
        );
      } else {
        orderId = kIsWeb ? _currentOrder!.documentId : _currentOrder!.id;
        if (orderId == null) {
          orderId = await _orderService.createOrder(
            dbProvider: dbProvider,
            orderType: _orderType,
            tableId: _selectedTableId,
            createdBy: authProvider.currentUserId != null
                ? (kIsWeb
                    ? authProvider.currentUserId!
                    : int.tryParse(authProvider.currentUserId!))
                : null,
          );
        }
      }

      await _orderService.addItemToOrder(
        dbProvider: dbProvider,
        context: context,
        orderId: orderId,
        product: product,
        quantity: 1,
        createdBy: authProvider.currentUserId != null
            ? (kIsWeb
                ? authProvider.currentUserId!
                : int.tryParse(authProvider.currentUserId!))
            : null,
      );

      final updatedOrder =
          await _orderService.getOrderById(dbProvider, orderId);
      if (mounted) {
        final persistedProductId =
            kIsWeb ? product.documentId : product.id;
        setState(() {
          _currentOrder = updatedOrder;
          final newOpt = _optimisticItems.toList();
          final idx = newOpt.indexWhere((i) => i.productId == persistedProductId);
          if (idx >= 0) newOpt.removeAt(idx);
          _optimisticItems = newOpt;
          if (_optimisticItems.isEmpty) {
            _optimisticOrder = null;
          } else {
            final base = updatedOrder!;
            double sub = base.subtotal;
            for (final oi in _optimisticItems) {
              sub += oi.totalPrice;
            }
            final dPct = base.discountPercent;
            final dAmt = sub * (dPct / 100);
            _optimisticOrder = base.copyWith(
              subtotal: sub,
              discountAmount: dAmt,
              totalAmount: sub - dAmt,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
          }
        });
        _processPendingPersist();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticOrder = null;
          _optimisticItems = [];
          _pendingPersist.clear();
          _isAddingItem = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add item: $e')),
        );
      }
    }
  }

  Future<void> _startNewOrder() async {
    if (!mounted) return;

    final hadOrder = _currentOrder != null;
    if (hadOrder) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start new order?'),
          content: const Text('This will clear the current cart.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('New Order'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final authProvider =
          Provider.of<InaraAuthProvider>(context, listen: false);
      await dbProvider.init();

      // If an order is already open, delete it so we truly start fresh.
      if (_currentOrder != null) {
        final orderId = kIsWeb ? _currentOrder!.documentId : _currentOrder!.id;
        if (orderId != null) {
          // Safe for pending orders; if it was paid, service handles ledger reversal.
          await _orderService.deleteOrder(
            dbProvider: dbProvider,
            context: context,
            orderId: orderId,
          );
        }
      }

      // Start a new blank order immediately so user sees a fresh cart.
      final newOrderId = await _orderService.createOrder(
        dbProvider: dbProvider,
        orderType: _orderType,
        tableId: _selectedTableId,
        createdBy: authProvider.currentUserId != null
            ? (kIsWeb
                ? authProvider.currentUserId!
                : int.tryParse(authProvider.currentUserId!))
            : null,
      );

      final newOrder = await _orderService.getOrderById(dbProvider, newOrderId);
      if (!mounted) return;

      setState(() {
        _currentOrder = newOrder;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New order started')),
      );
    } catch (e) {
      debugPrint('Error starting new order: $e');
      if (mounted) {
        setState(() {
          _currentOrder = null;
          _selectedTableId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to start new order: $e')),
        );
      }
    }
  }

  Future<void> _showPaymentDialog() async {
    if (_currentOrder == null ||
        _currentOrder!.totalAmount <= 0 ||
        _optimisticItems.isNotEmpty) {
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => POSPaymentDialog(
        order: _currentOrder!,
        orderService: _orderService,
      ),
    );

    if (result != null && result['success'] == true) {
      final orderId = result['order_id'];
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);

      try {
        await _printerService.printBill(dbProvider, orderId);
      } catch (e) {
        debugPrint('Print error: $e');
      }

      try {
        await _printerService.printKOT(dbProvider, orderId);
      } catch (e) {
        debugPrint('KOT print error: $e');
      }

      setState(() {
        _currentOrder = null;
        _selectedTableId = null;
        _optimisticOrder = null;
        _optimisticItems = [];
        _pendingPersist.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor:
            const Color(0xFFFFF8E1), // Warm cream background
      ),
      child: Scaffold(
        appBar: AppBar(
          elevation: 2,
          backgroundColor:
              AppTheme.logoLight.withOpacity(0.9), // Light golden app bar
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.point_of_sale, color: Color(0xFFFFC107)),
              ),
              const SizedBox(width: 12),
              const Text(
                'POS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'New Order',
              onPressed: _isAddingItem ? null : _startNewOrder,
              icon: const Icon(Icons.add_shopping_cart),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[700]!, width: 1),
              ),
              child: ToggleButtons(
                isSelected: [
                  _orderType == 'dine_in',
                  _orderType == 'takeaway',
                ],
                onPressed: (index) {
                  setState(() {
                    _orderType = index == 0 ? 'dine_in' : 'takeaway';
                    if (_orderType == 'takeaway') {
                      _selectedTableId = null;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                color: Colors.grey[400],
                fillColor: Theme.of(context).primaryColor,
                constraints: const BoxConstraints(
                  minHeight: 36,
                  minWidth: 80,
                ),
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('Dine-In'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('Takeaway'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                // Product Grid (70% width)
                Expanded(
                  flex: 7,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      border: Border(
                        right: BorderSide(color: Colors.grey[800]!, width: 1),
                      ),
                    ),
                    child: POSProductGrid(
                      onProductSelected: _addProductToCart,
                      orderType: _orderType,
                    ),
                  ),
                ),

                // Cart (30% width) - Constrained to prevent overflow
                SizedBox(
                  width: (constraints.maxWidth * 0.3).clamp(280.0, 420.0),
                  child: POSCartWidget(
                    order: _currentOrder,
                    orderType: _orderType,
                    selectedTableId: _selectedTableId,
                    optimisticOrder: _optimisticOrder,
                    optimisticItems: _optimisticItems,
                    onOrderUpdated: (order) {
                      setState(() {
                        _currentOrder = order;
                      });
                    },
                    onTableSelected: (tableId) {
                      setState(() {
                        _selectedTableId = tableId;
                      });
                    },
                    onPayPressed: _showPaymentDialog,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
