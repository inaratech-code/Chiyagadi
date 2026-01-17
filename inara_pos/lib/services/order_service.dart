import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/unified_database_provider.dart';
import '../providers/auth_provider.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/product.dart';
import 'inventory_ledger_service.dart';

/// Order Service
///
/// FIXED: Now uses InventoryLedgerService instead of direct inventory updates
/// Stock is calculated from ledger entries, never stored directly
class OrderService {
  final InventoryLedgerService _ledgerService = InventoryLedgerService();

  // Generate unique order number (ORD yymmdd/000 format)
  Future<String> generateOrderNumber(UnifiedDatabaseProvider dbProvider) async {
    await dbProvider.init();
    final now = DateTime.now();
    // Format: yymmdd (2-digit year, 2-digit month, 2-digit day)
    final year = now.year % 100; // Get last 2 digits of year
    final dateStr =
        '${year.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    // Get start and end of today
    final startOfDay =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59)
        .millisecondsSinceEpoch;

    // Find all orders created today with the ORD prefix
    final todayOrders = await dbProvider.query(
      'orders',
      where: 'created_at >= ? AND created_at <= ? AND order_number LIKE ?',
      whereArgs: [startOfDay, endOfDay, 'ORD $dateStr/%'],
    );

    // Extract sequential numbers from today's orders
    // FIXED: Start from 0 so first order is 001 (not 000)
    int maxSequence = 0;
    final pattern = RegExp(r'ORD \d{6}/(\d+)');

    for (final order in todayOrders) {
      final orderNumber = order['order_number'] as String;
      final match = pattern.firstMatch(orderNumber);
      if (match != null) {
        final sequence = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (sequence > maxSequence) {
          maxSequence = sequence;
        }
      }
    }

    // Increment sequence number (start from 001)
    final nextSequence = maxSequence + 1;
    final sequenceStr = nextSequence.toString().padLeft(3, '0');

    return 'ORD $dateStr/$sequenceStr';
  }

  // Create new order
  // FIXED: createdBy can be int (SQLite) or String (Firestore)
  Future<dynamic> createOrder({
    required UnifiedDatabaseProvider dbProvider,
    required String orderType,
    dynamic tableId, // Can be int (SQLite) or String (Firestore)
    dynamic createdBy, // FIXED: Can be int (SQLite) or String (Firestore)
  }) async {
    await dbProvider.init();
    final now = DateTime.now().millisecondsSinceEpoch;
    final orderNumber = await generateOrderNumber(dbProvider);

    // FIXED: Get default VAT rate from settings
    final defaultVatPercent = await _getTaxRate(dbProvider);

    final orderId = await dbProvider.insert('orders', {
      'order_number': orderNumber,
      'table_id': tableId,
      'order_type': orderType,
      'status': 'pending',
      'subtotal': 0,
      'discount_amount': 0,
      'discount_percent': 0,
      'tax_amount': 0,
      'tax_percent': defaultVatPercent, // FIXED: Set default VAT percent
      'total_amount': 0,
      'payment_status': 'unpaid',
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
      'synced': 0,
    });

    return orderId;
  }

  // Add item to order (with stock check using ledger)
  Future<void> addItemToOrder({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderId,
    required Product product,
    required int quantity,
    String? notes,
  }) async {
    await dbProvider.init();

    // FIXED: Only allow sellable products (menu items) to be added to orders
    // Purchase items (raw materials) cannot be sold
    if (!product.isSellable) {
      throw Exception(
          'This product cannot be sold. Only menu items can be added to orders.');
    }

    // FIXED: Check stock availability using ledger calculation
    final productId = kIsWeb ? product.documentId : product.id;
    if (productId == null) {
      throw Exception('Product ID is required');
    }

    final availableStock = await _ledgerService.getCurrentStock(
      context: context,
      productId: productId,
    );
    final currentOrderQty =
        await _getCurrentOrderQuantity(dbProvider, orderId, productId);
    final totalRequired = currentOrderQty + quantity;

    if (totalRequired > availableStock) {
      throw Exception(
          'Insufficient stock. Available: $availableStock, Required: $totalRequired');
    }

    final unitPrice = product.price;
    final totalPrice = unitPrice * quantity;

    // Check if item already exists in order
    final existingItems = await dbProvider.query(
      'order_items',
      where: 'order_id = ? AND product_id = ?',
      whereArgs: [orderId, productId],
    );

    if (existingItems.isNotEmpty) {
      // Update quantity
      final existingItem = existingItems.first;
      // FIXED: Handle both int and double for quantity
      final currentQty = (existingItem['quantity'] as num?)?.toInt() ?? 0;
      final newQuantity = currentQty + quantity;
      final newTotalPrice = unitPrice * newQuantity;

      // FIXED: Handle both int and String for order item ID
      final itemId = existingItem['id'];

      await dbProvider.update(
        'order_items',
        values: {
          'quantity': newQuantity,
          'total_price': newTotalPrice,
          'notes': notes ?? existingItem['notes'],
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [itemId],
      );
    } else {
      // Insert new item
      await dbProvider.insert('order_items', {
        'order_id': orderId,
        'product_id': productId,
        'product_name': product.name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
        'notes': notes,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // Recalculate order totals
    await _recalculateOrderTotals(dbProvider, orderId);
  }

  // Get current quantity of product in order
  // FIXED: Accept dynamic productId (int for SQLite, String for Firestore)
  Future<int> _getCurrentOrderQuantity(UnifiedDatabaseProvider dbProvider,
      dynamic orderId, dynamic productId) async {
    final items = await dbProvider.query(
      'order_items',
      where: 'order_id = ? AND product_id = ?',
      whereArgs: [orderId, productId],
    );

    if (items.isEmpty) return 0;
    // FIXED: Handle both int and double for quantity
    final quantityData = items.first['quantity'];
    if (quantityData is int) {
      return quantityData;
    } else if (quantityData is double) {
      return quantityData.toInt();
    } else if (quantityData is num) {
      return quantityData.toInt();
    }
    return 0;
  }

  // Remove item from order
  // FIXED: Handle both int (SQLite) and String (Firestore) order item IDs
  Future<void> removeItemFromOrder(
      UnifiedDatabaseProvider dbProvider, dynamic orderItemId) async {
    await dbProvider.init();
    // Get order_id before deleting
    final item = await dbProvider.query(
      'order_items',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderItemId],
    );

    if (item.isNotEmpty) {
      final orderId = item.first['order_id'];
      await dbProvider.delete(
        'order_items',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [orderItemId],
      );
      await _recalculateOrderTotals(dbProvider, orderId);
    }
  }

  // Update item quantity
  Future<void> updateItemQuantity(UnifiedDatabaseProvider dbProvider,
      dynamic orderItemId, int quantity) async {
    await dbProvider.init();
    if (quantity <= 0) {
      await removeItemFromOrder(dbProvider, orderItemId);
      return;
    }

    // Get item details
    final item = await dbProvider.query(
      'order_items',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderItemId],
    );

    if (item.isNotEmpty) {
      final unitPrice = (item.first['unit_price'] as num).toDouble();
      final totalPrice = unitPrice * quantity;
      final orderId = item.first['order_id'];

      await dbProvider.update(
        'order_items',
        values: {
          'quantity': quantity,
          'total_price': totalPrice,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [orderItemId],
      );

      await _recalculateOrderTotals(dbProvider, orderId);
    }
  }

  // Apply discount
  Future<void> applyDiscount({
    required UnifiedDatabaseProvider dbProvider,
    required dynamic orderId,
    double? discountPercent,
    double? discountAmount,
  }) async {
    await dbProvider.init();
    final order = await getOrderById(dbProvider, orderId);
    if (order == null) return;

    double finalDiscountPercent = discountPercent ?? 0;
    double finalDiscountAmount = discountAmount ?? 0;

    if (discountPercent != null && discountPercent > 0) {
      finalDiscountAmount = order.subtotal * (discountPercent / 100);
    }

    // Get VAT rate from settings (default 13% VAT in Nepal)
    final taxRate = await _getTaxRate(dbProvider);
    final discountedSubtotal = order.subtotal - finalDiscountAmount;
    final taxAmount = discountedSubtotal * (taxRate / 100);
    final totalAmount = discountedSubtotal + taxAmount;

    await dbProvider.update(
      'orders',
      values: {
        'discount_percent': finalDiscountPercent,
        'discount_amount': finalDiscountAmount,
        'tax_percent': taxRate,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );
  }

  // Update VAT and Discount with auto-calculation
  Future<void> updateVATAndDiscount({
    required UnifiedDatabaseProvider dbProvider,
    required dynamic orderId,
    required double vatPercent,
    required double discountPercent,
  }) async {
    await dbProvider.init();
    final order = await getOrderById(dbProvider, orderId);
    if (order == null) {
      debugPrint('Order not found for ID: $orderId');
      return;
    }

    // FIXED: Recalculate subtotal from current order items (in case items changed)
    final items = await dbProvider.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    double subtotal = 0;
    for (final item in items) {
      subtotal += (item['total_price'] as num).toDouble();
    }

    // Calculate discount amount from percentage
    final discountAmount = subtotal * (discountPercent / 100);
    final discountedSubtotal = subtotal - discountAmount;

    // Calculate VAT on discounted subtotal
    final taxAmount = discountedSubtotal * (vatPercent / 100);
    final totalAmount = discountedSubtotal + taxAmount;

    debugPrint(
        'VAT/Discount Update - Subtotal: $subtotal, Discount %: $discountPercent, Discount Amount: $discountAmount, VAT %: $vatPercent, VAT Amount: $taxAmount, Total: $totalAmount');

    await dbProvider.update(
      'orders',
      values: {
        'subtotal': subtotal,
        'discount_percent': discountPercent,
        'discount_amount': discountAmount,
        'tax_percent': vatPercent,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );
  }

  // Recalculate order totals
  Future<void> _recalculateOrderTotals(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    await dbProvider.init();
    final items = await dbProvider.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    double subtotal = 0;
    for (final item in items) {
      subtotal += (item['total_price'] as num).toDouble();
    }

    // Get current discount and VAT from order
    final order = await getOrderById(dbProvider, orderId);
    final discountPercent = order?.discountPercent ?? 0;

    // FIXED: Recalculate discount amount from percentage based on new subtotal
    final discountAmount = subtotal * (discountPercent / 100);

    // FIXED: Use VAT percent from order, default to 13% if 0 or null
    double vatPercent = order?.taxPercent ?? 0;
    if (vatPercent == 0) {
      // If VAT is 0, get default from settings
      vatPercent = await _getTaxRate(dbProvider);
    }

    final discountedSubtotal = subtotal - discountAmount;
    final taxAmount = discountedSubtotal * (vatPercent / 100);
    final totalAmount = discountedSubtotal + taxAmount;

    await dbProvider.update(
      'orders',
      values: {
        'subtotal': subtotal,
        'discount_percent': discountPercent,
        'discount_amount':
            discountAmount, // FIXED: Update discount amount when recalculating
        'tax_percent': vatPercent, // FIXED: Update VAT percent if it was 0
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );
  }

  // Get order by ID
  Future<Order?> getOrderById(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    await dbProvider.init();
    // FIXED: Handle both SQLite (id) and Firestore (documentId) queries
    final orders = await dbProvider.query(
      'orders',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );

    if (orders.isEmpty) return null;
    return Order.fromMap(orders.first);
  }

  // Get order items
  /// Get order items as maps (for ledger entries and other uses)
  Future<List<Map<String, dynamic>>> getOrderItems(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    await dbProvider.init();
    final items = await dbProvider.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'created_at ASC',
    );

    // Return items with product_name for ledger entries
    // The order_items table should have product_name denormalized
    return items;
  }

  /// Get order items as OrderItem objects (for UI display)
  Future<List<OrderItem>> getOrderItemsAsObjects(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    final items = await getOrderItems(dbProvider, orderId);
    return items.map((item) => OrderItem.fromMap(item)).toList();
  }

  // Confirm order (change status to confirmed)
  Future<void> confirmOrder(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    await dbProvider.init();
    await dbProvider.update(
      'orders',
      values: {
        'status': 'confirmed',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );
  }

  // Cancel order (change status to cancelled)
  Future<void> cancelOrder(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    await dbProvider.init();
    await dbProvider.update(
      'orders',
      values: {
        'status': 'cancelled',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );
  }

  // Delete order (permanently remove order and its items)
  // FIXED: Handle both SQLite (id) and Firestore (documentId) queries
  // FIXED: Reverse inventory ledger entries if order was paid
  Future<void> deleteOrder({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderId,
  }) async {
    await dbProvider.init();

    // Get order details first to check if it was paid
    final order = await getOrderById(dbProvider, orderId);
    if (order == null) {
      throw Exception('Order not found');
    }

    final wasPaid = order.paymentStatus == 'paid';
    final orderItems = await getOrderItems(dbProvider, orderId);

    // If order was paid, reverse inventory ledger entries (add back stock)
    if (wasPaid && orderItems.isNotEmpty) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final createdBy = authProvider.currentUserId != null
          ? (kIsWeb
              ? authProvider.currentUserId!
              : int.tryParse(authProvider.currentUserId!))
          : null;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Use transaction to ensure all reverse entries are created atomically
      await dbProvider.transaction((txn) async {
        for (final item in orderItems) {
          final productId = item['product_id'];
          final productName =
              item['product_name'] as String? ?? 'Unknown Product';
          final quantityOut = (item['quantity'] as num).toDouble();

          // Create reverse entry: quantityIn = quantityOut (add back stock)
          await txn.insert('inventory_ledger', {
            'product_id': productId,
            'product_name': productName,
            'quantity_in': quantityOut, // Add back the stock
            'quantity_out': 0.0,
            'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
            'transaction_type': 'adjustment',
            'reference_type': 'order_deletion',
            'reference_id': orderId,
            'notes': 'Stock returned: Order ${order.orderNumber} deleted',
            'created_by': createdBy,
            'created_at': now,
          });
        }
      });
    }

    // Delete all order items first
    await dbProvider.delete(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    // Then, delete the order itself
    await dbProvider.delete(
      'orders',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );
  }

  // Complete payment (supports partial payment and credit)
  // FIXED: Added BuildContext parameter for ledger service
  Future<void> completePayment({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderId,
    required String paymentMethod,
    required double amount,
    dynamic customerId, // int (SQLite) or String (Firestore)
    double? partialAmount,
    dynamic createdBy, // FIXED: Can be int (SQLite) or String (Firestore)
    String? transactionId,
  }) async {
    await dbProvider.init();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get order details
    final orders = await dbProvider.query(
      'orders',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );

    if (orders.isEmpty) {
      throw Exception('Order not found');
    }

    final order = orders.first;
    final totalAmount = (order['total_amount'] as num).toDouble();
    final paidAmount = (order['paid_amount'] as num? ?? 0).toDouble();

    // Calculate payment amounts
    double newPaidAmount;
    double creditAmount = 0.0;
    String paymentStatus;

    if (paymentMethod == 'credit') {
      // Credit payment: allow optional paid-now amount (partialAmount) and the rest becomes credit.
      final paidNow =
          (partialAmount != null && partialAmount > 0) ? partialAmount : 0.0;
      newPaidAmount = paidAmount + paidNow;
      creditAmount = (totalAmount - newPaidAmount).clamp(0.0, double.infinity);
      paymentStatus = creditAmount > 0 ? 'partial' : 'paid';
    } else if (partialAmount != null && partialAmount > 0) {
      // Partial payment (non-credit): remaining becomes credit_amount only if you later choose credit elsewhere.
      newPaidAmount = paidAmount + partialAmount;
      creditAmount = totalAmount - newPaidAmount;
      paymentStatus = creditAmount > 0 ? 'partial' : 'paid';
    } else {
      // Full payment
      newPaidAmount = totalAmount;
      creditAmount = 0.0;
      paymentStatus = 'paid';
    }

    // NOTE: Firestore web transactions are sensitive to reads performed via normal
    // queries inside the transaction callback and can throw opaque JS errors.
    // For web we use a safe, sequential write approach; for SQLite we keep the transaction.
    final updateData = {
      'payment_status': paymentStatus,
      'payment_method': paymentMethod,
      'customer_id': customerId,
      'credit_amount': creditAmount,
      'paid_amount': newPaidAmount,
      'status': paymentStatus == 'paid' ? 'completed' : 'confirmed',
      'updated_at': now,
    };

    if (kIsWeb) {
      // 1) Insert payment record
      // For credit, insert only if some amount was received now (partialAmount).
      final paidNow = paymentMethod == 'credit'
          ? (partialAmount ?? 0.0)
          : (partialAmount ?? amount);
      if (paidNow > 0) {
        await dbProvider.insert('payments', {
          'order_id': orderId,
          'amount': paidNow,
          'payment_method': paymentMethod,
          'transaction_id': transactionId,
          'created_by': createdBy,
          'created_at': now,
          'synced': 0,
        });
      }

      // 2) Update order
      await dbProvider.update(
        'orders',
        values: updateData,
        where: 'documentId = ?',
        whereArgs: [orderId.toString()],
      );

      // 3) Update customer credit if needed (best-effort)
      if (creditAmount > 0 && customerId != null) {
        // customerId might be an int (legacy) or a string doc id depending on how customer selection works
        final customerDocs = await dbProvider.query(
          'customers',
          where: customerId is String ? 'documentId = ?' : 'id = ?',
          whereArgs: [customerId],
        );

        if (customerDocs.isNotEmpty) {
          final customer = customerDocs.first;
          final currentBalance =
              (customer['credit_balance'] as num? ?? 0).toDouble();
          final newBalance = currentBalance + creditAmount;

          final customerDocId = (customer['id'] as String?) ??
              (customer['documentId'] as String?);
          if (customerDocId != null) {
            await dbProvider.update(
              'customers',
              values: {
                'credit_balance': newBalance,
                'updated_at': now,
              },
              where: 'documentId = ?',
              whereArgs: [customerDocId],
            );
          }

          await dbProvider.insert('credit_transactions', {
            'customer_id': customerId,
            'order_id': orderId,
            'transaction_type': 'credit',
            'amount': creditAmount,
            'balance_before': currentBalance,
            'balance_after': newBalance,
            'notes': 'Order payment: ${order['order_number']}',
            'created_by': createdBy,
            'created_at': now,
            'synced': 0,
          });
        }
      }
    } else {
      // SQLite: Use transaction to ensure atomicity
      final intCustomerId = customerId is int
          ? customerId
          : int.tryParse(customerId?.toString() ?? '');
      await dbProvider.transaction((txn) async {
        final paidNow = paymentMethod == 'credit'
            ? (partialAmount ?? 0.0)
            : (partialAmount ?? amount);
        if (paidNow > 0) {
          await txn.insert('payments', {
            'order_id': orderId,
            'amount': paidNow,
            'payment_method': paymentMethod,
            'transaction_id': transactionId,
            'created_by': createdBy,
            'created_at': now,
            'synced': 0,
          });
        }

        await txn.update(
          'orders',
          updateData,
          where: 'id = ?',
          whereArgs: [orderId],
        );

        if (creditAmount > 0 && intCustomerId != null) {
          final customers = await txn.query(
            'customers',
            where: 'id = ?',
            whereArgs: [intCustomerId],
          );

          if (customers.isNotEmpty) {
            final customer = customers.first;
            final currentBalance =
                (customer['credit_balance'] as num? ?? 0).toDouble();
            final newBalance = currentBalance + creditAmount;

            await txn.update(
              'customers',
              {
                'credit_balance': newBalance,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [intCustomerId],
            );

            await txn.insert('credit_transactions', {
              'customer_id': intCustomerId,
              'order_id': orderId,
              'transaction_type': 'credit',
              'amount': creditAmount,
              'balance_before': currentBalance,
              'balance_after': newBalance,
              'notes': 'Order payment: ${order['order_number']}',
              'created_by': createdBy,
              'created_at': now,
              'synced': 0,
            });
          }
        }
      });
    }

    // FIXED: Deduct inventory using ledger entries (not direct updates)
    await _deductInventory(
      dbProvider: dbProvider,
      context: context,
      orderId: orderId,
    );
  }

  // Pay credit (reduce customer balance when credit is paid later)
  Future<void> payCredit({
    required UnifiedDatabaseProvider dbProvider,
    required dynamic orderId,
    required double amount,
    String paymentMethod = 'cash',
    dynamic createdBy, // FIXED: Can be int (SQLite) or String (Firestore)
  }) async {
    await dbProvider.init();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get order details
    final orders = await dbProvider.query(
      'orders',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderId],
    );

    if (orders.isEmpty) {
      throw Exception('Order not found');
    }

    final order = orders.first;
    final customerId = order['customer_id'] as int?;
    final currentCredit = (order['credit_amount'] as num? ?? 0).toDouble();
    final currentPaid = (order['paid_amount'] as num? ?? 0).toDouble();

    if (customerId == null) {
      throw Exception('Order has no customer assigned');
    }

    if (currentCredit <= 0) {
      throw Exception('Order has no credit amount');
    }

    final paymentAmount = amount > currentCredit ? currentCredit : amount;
    final newCredit = currentCredit - paymentAmount;
    final newPaid = currentPaid + paymentAmount;
    final paymentStatus = newCredit > 0 ? 'partial' : 'paid';

    // Use transaction to ensure atomicity
    await dbProvider.transaction((txn) async {
      // Insert payment record
      await txn.insert('payments', {
        'order_id': orderId,
        'amount': paymentAmount,
        'payment_method': paymentMethod,
        'created_by': createdBy,
        'created_at': now,
        'synced': 0,
      });

      // FIXED: Update order - unified approach
      final orderUpdateData = {
        'credit_amount': newCredit,
        'paid_amount': newPaid,
        'payment_status': paymentStatus,
        'status': paymentStatus == 'paid' ? 'completed' : 'confirmed',
        'updated_at': now,
      };

      if (kIsWeb) {
        await txn.update('orders', orderId.toString(), orderUpdateData);
      } else {
        await txn.update('orders', orderUpdateData,
            where: 'id = ?', whereArgs: [orderId]);
      }

      // FIXED: Update customer credit balance - unified approach
      final customers = await txn.query(
        'customers',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [customerId.toString()],
      );

      // FIXED: Handle customer update and credit transaction creation
      double? currentBalance;
      double? newBalance;
      bool customerUpdated = false;

      if (customers.isEmpty && kIsWeb) {
        // Try by id field for Firestore
        final customersById = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [customerId],
        );
        if (customersById.isNotEmpty) {
          final customer = customersById.first;
          final cb = (customer['credit_balance'] as num? ?? 0).toDouble();
          final nb = (cb - paymentAmount).clamp(0.0, double.infinity);
          currentBalance = cb;
          newBalance = nb;

          final docId = customer['id'] as String;
          await txn.update('customers', docId, {
            'credit_balance': nb,
            'updated_at': now,
          });
          customerUpdated = true;
        }
      } else if (customers.isNotEmpty) {
        final customer = customers.first;
        final cb = (customer['credit_balance'] as num? ?? 0).toDouble();
        final nb = (cb - paymentAmount).clamp(0.0, double.infinity);
        currentBalance = cb;
        newBalance = nb;

        if (kIsWeb) {
          final docId = customer['id'] as String;
          await txn.update('customers', docId, {
            'credit_balance': nb,
            'updated_at': now,
          });
        } else {
          await txn.update(
              'customers',
              {
                'credit_balance': nb,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [customerId]);
        }
        customerUpdated = true;
      }

      // Create payment transaction if customer was updated
      if (customerUpdated && currentBalance != null && newBalance != null) {
        await txn.insert('credit_transactions', {
          'customer_id': customerId,
          'order_id': orderId,
          'transaction_type': 'payment',
          'amount': paymentAmount,
          'balance_before': currentBalance,
          'balance_after': newBalance,
          'notes': 'Credit payment for order: ${order['order_number']}',
          'created_by': createdBy,
          'created_at': now,
          'synced': 0,
        });
      }
    });
  }

  /// FIXED: Deduct inventory on sale using ledger entries (transactional, prevents negative stock)
  ///
  /// This method:
  /// 1. Gets all order items
  /// 2. For each item, checks current stock from ledger
  /// 3. Prevents negative stock
  /// 4. Creates inventory_ledger entries (quantityOut) for each item
  ///
  /// Stock is NEVER directly updated - only ledger entries are created
  Future<void> _deductInventory({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderId,
  }) async {
    final items = await getOrderItems(dbProvider, orderId);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // FIXED: Handle both int (SQLite) and String (Firestore) user IDs
    final createdBy = authProvider.currentUserId != null
        ? (kIsWeb
            ? authProvider.currentUserId!
            : int.tryParse(authProvider.currentUserId!))
        : null;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (kIsWeb) {
      // Web/Firestore: avoid transactions here (can throw opaque JS errors when mixed with reads).
      for (final item in items) {
        // Check stock availability using ledger calculation
        final productId = item['product_id'];
        final currentStock = await _ledgerService.getCurrentStock(
          context: context,
          productId: productId,
        );

        final requiredQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final productName =
            item['product_name'] as String? ?? 'Unknown Product';

        if (currentStock < requiredQty) {
          throw Exception(
            'Insufficient stock for $productName. Available: $currentStock, Required: $requiredQty',
          );
        }

        await dbProvider.insert('inventory_ledger', {
          'product_id': item['product_id'],
          'product_name': productName,
          'quantity_in': 0.0,
          'quantity_out': requiredQty,
          'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
          'transaction_type': 'sale',
          'reference_type': 'sale',
          'reference_id': orderId,
          'notes': 'Sale: Order $orderId',
          'created_by': createdBy,
          'created_at': now,
        });
      }
    } else {
      // SQLite: Use transaction to ensure all ledger entries are created atomically
      await dbProvider.transaction((txn) async {
        for (final item in items) {
          try {
            final productId = item['product_id'];
            final currentStock = await _ledgerService.getCurrentStock(
              context: context,
              productId: productId,
            );

            final requiredQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            final productName =
                item['product_name'] as String? ?? 'Unknown Product';

            if (currentStock < requiredQty) {
              throw Exception(
                'Insufficient stock for $productName. '
                'Available: $currentStock, Required: $requiredQty',
              );
            }

            await txn.insert('inventory_ledger', {
              'product_id': item['product_id'],
              'product_name': productName,
              'quantity_in': 0.0,
              'quantity_out': requiredQty,
              'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
              'transaction_type': 'sale',
              'reference_type': 'sale',
              'reference_id': orderId,
              'notes': 'Sale: Order $orderId',
              'created_by': createdBy,
              'created_at': now,
            });
          } catch (e) {
            debugPrint('Error creating ledger entry for sale: $e');
            rethrow;
          }
        }
      });
    }
  }

  // Get VAT rate from settings (default 13% VAT in Nepal)
  Future<double> _getTaxRate(UnifiedDatabaseProvider dbProvider) async {
    await dbProvider.init();
    final settings = await dbProvider.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['tax_percent'],
    );

    if (settings.isNotEmpty) {
      return double.tryParse(settings.first['value'] as String) ?? 13.0;
    }

    // Default 13% VAT for Nepal
    return 13.0;
  }
}
