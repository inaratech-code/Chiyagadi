import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../models/product.dart';
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
  String _orderType = 'dine_in'; // 'dine_in' or 'takeaway'
  int? _selectedTableId;

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

  Future<void> _addProductToCart(Product product) async {
    if (_currentOrder == null) {
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final now = DateTime.now().millisecondsSinceEpoch;
      final orderNumber = await _orderService.generateOrderNumber(dbProvider);
      setState(() {
        _currentOrder = Order(
          orderNumber: orderNumber,
          orderType: _orderType,
          tableId: _selectedTableId,
          createdAt: now,
          updatedAt: now,
        );
      });
    }
  }

  Future<void> _showPaymentDialog() async {
    if (_currentOrder == null || _currentOrder!.totalAmount <= 0) {
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
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      
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
        scaffoldBackgroundColor: const Color(0xFFFFF8E1), // Warm cream background
      ),
      child: Scaffold(
        appBar: AppBar(
          elevation: 2,
          backgroundColor: AppTheme.logoLight.withOpacity(0.9), // Light golden app bar
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.point_of_sale, color: Color(0xFFFFC107)),
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
