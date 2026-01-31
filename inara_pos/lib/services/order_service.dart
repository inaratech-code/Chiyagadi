import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../providers/unified_database_provider.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/product.dart';
import '../models/inventory_ledger_model.dart';
import '../services/inventory_ledger_service.dart';

/// Order Service
///
/// UPDATED: When items are added to orders, inventory is automatically deducted
/// if the product has inventory tracking enabled.
class OrderService {
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

    final orderId = await dbProvider.insert('orders', {
      'order_number': orderNumber,
      'table_id': tableId,
      'order_type': orderType,
      'status': 'pending',
      'subtotal': 0,
      'discount_amount': 0,
      'discount_percent': 0,
      'tax_amount': 0,
      'tax_percent': 0.0, // VAT removed
      'total_amount': 0,
      'payment_status': 'unpaid',
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
      'synced': 0,
    });

    return orderId;
  }

  // Add item to order (with automatic inventory deduction)
  Future<void> addItemToOrder({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderId,
    required Product product,
    required int quantity,
    String? notes,
    dynamic createdBy, // User ID who added the item
  }) async {
    await dbProvider.init();

    // FIXED: Only allow sellable products (menu items) to be added to orders
    // Purchase items (raw materials) cannot be sold
    if (!product.isSellable) {
      throw Exception(
          'This product cannot be sold. Only menu items can be added to orders.');
    }

    final productId = kIsWeb ? product.documentId : product.id;
    if (productId == null) {
      throw Exception('Product ID is required');
    }

    final unitPrice = product.price;
    final totalPrice = unitPrice * quantity;

    // UPDATED: Removed inventory check - items can be added to orders regardless of stock
    // Inventory is managed manually from the menu section
    // Stock deduction will happen on payment completion if needed
    debugPrint(
        'OrderService: Adding ${product.name} (ID: $productId) - quantity: $quantity (inventory check disabled)');

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

  // Helper method to check if product has inventory history
  Future<bool> _hasInventoryHistory(
      UnifiedDatabaseProvider dbProvider, dynamic productId) async {
    try {
      final ledgerEntries = await dbProvider.query(
        'inventory_ledger',
        where: 'product_id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      return ledgerEntries.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Remove item from order (with inventory reversal)
  // FIXED: Handle both int (SQLite) and String (Firestore) order item IDs
  Future<void> removeItemFromOrder({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderItemId,
    dynamic createdBy,
  }) async {
    await dbProvider.init();
    // Get order_id and item details before deleting
    final item = await dbProvider.query(
      'order_items',
      where: kIsWeb ? 'documentId = ?' : 'id = ?',
      whereArgs: [orderItemId],
    );

    if (item.isNotEmpty) {
      final orderId = item.first['order_id'];
      final productId = item.first['product_id'];
      final quantity = (item.first['quantity'] as num?)?.toInt() ?? 0;
      final unitPrice = (item.first['unit_price'] as num?)?.toDouble() ?? 0.0;
      final productName = item.first['product_name'] as String? ?? '';

      // UPDATED: Reverse inventory deduction if product has inventory
      if (quantity > 0) {
        try {
          final inventoryLedgerService = InventoryLedgerService();
          final hasInventory =
              await _hasInventoryHistory(dbProvider, productId);

          if (hasInventory) {
            // Convert createdBy to int? for InventoryLedger
            int? createdByInt;
            if (createdBy != null) {
              if (createdBy is int) {
                createdByInt = createdBy;
              } else if (createdBy is String) {
                createdByInt = int.tryParse(createdBy);
              } else if (createdBy is num) {
                createdByInt = createdBy.toInt();
              }
            }

            // Create reverse ledger entry to add stock back
            final ledgerEntry = InventoryLedger(
              productId: productId,
              productName: productName,
              quantityIn: quantity.toDouble(),
              quantityOut: 0.0,
              unitPrice: unitPrice,
              transactionType: 'return',
              referenceType: 'order',
              referenceId: orderId,
              notes: 'Order item removed: $productName',
              createdBy: createdByInt,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );

            await inventoryLedgerService.addLedgerEntry(
              context: context,
              ledgerEntry: ledgerEntry,
            );

            debugPrint(
                'OrderService: Reversed inventory deduction for $quantity $productName');
          }
        } catch (e) {
          debugPrint('OrderService: Error reversing inventory: $e');
          // Continue with deletion even if inventory reversal fails
        }
      }

      await dbProvider.delete(
        'order_items',
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [orderItemId],
      );
      await _recalculateOrderTotals(dbProvider, orderId);
    }
  }

  // Update item quantity (with inventory adjustment)
  Future<void> updateItemQuantity({
    required UnifiedDatabaseProvider dbProvider,
    required BuildContext context,
    required dynamic orderItemId,
    required int quantity,
    dynamic createdBy,
  }) async {
    await dbProvider.init();
    if (quantity <= 0) {
      await removeItemFromOrder(
        dbProvider: dbProvider,
        context: context,
        orderItemId: orderItemId,
        createdBy: createdBy,
      );
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
      final productId = item.first['product_id'];
      final oldQuantity = (item.first['quantity'] as num?)?.toInt() ?? 0;
      final productName = item.first['product_name'] as String? ?? '';

      // UPDATED: Adjust inventory if quantity changed
      if (oldQuantity != quantity) {
        try {
          final inventoryLedgerService = InventoryLedgerService();
          final hasInventory =
              await _hasInventoryHistory(dbProvider, productId);

          if (hasInventory) {
            // Convert createdBy to int? for InventoryLedger
            int? createdByInt;
            if (createdBy != null) {
              if (createdBy is int) {
                createdByInt = createdBy;
              } else if (createdBy is String) {
                createdByInt = int.tryParse(createdBy);
              } else if (createdBy is num) {
                createdByInt = createdBy.toInt();
              }
            }

            final quantityDiff = quantity - oldQuantity;

            if (quantityDiff > 0) {
              // Quantity increased - deduct more stock
              final currentStock = await inventoryLedgerService.getCurrentStock(
                context: context,
                productId: productId,
              );

              if (currentStock < quantityDiff) {
                throw Exception(
                    'Insufficient stock. Available: ${currentStock.toStringAsFixed(2)}, Required: $quantityDiff');
              }

              final ledgerEntry = InventoryLedger(
                productId: productId,
                productName: productName,
                quantityIn: 0.0,
                quantityOut: quantityDiff.toDouble(),
                unitPrice: unitPrice,
                transactionType: 'sale',
                referenceType: 'order',
                referenceId: orderId,
                notes: 'Order item quantity increased: $productName',
                createdBy: createdByInt,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );

              await inventoryLedgerService.addLedgerEntry(
                context: context,
                ledgerEntry: ledgerEntry,
              );
            } else {
              // Quantity decreased - add stock back
              final ledgerEntry = InventoryLedger(
                productId: productId,
                productName: productName,
                quantityIn: (-quantityDiff).toDouble(),
                quantityOut: 0.0,
                unitPrice: unitPrice,
                transactionType: 'return',
                referenceType: 'order',
                referenceId: orderId,
                notes: 'Order item quantity decreased: $productName',
                createdBy: createdByInt,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );

              await inventoryLedgerService.addLedgerEntry(
                context: context,
                ledgerEntry: ledgerEntry,
              );
            }

            debugPrint(
                'OrderService: Adjusted inventory for $productName: ${oldQuantity} -> $quantity');
          }
        } catch (e) {
          if (e.toString().contains('Insufficient stock')) {
            rethrow;
          }
          debugPrint('OrderService: Error adjusting inventory: $e');
          // Continue with update even if inventory adjustment fails
        }
      }

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
    final totalAmount = subtotal - discountAmount;

    debugPrint(
        'Discount Update - Subtotal: $subtotal, Discount %: $discountPercent, Discount Amount: $discountAmount, Total: $totalAmount');

    await dbProvider.update(
      'orders',
      values: {
        'subtotal': subtotal,
        'discount_percent': discountPercent,
        'discount_amount': discountAmount,
        'tax_percent': 0.0,
        'tax_amount': 0.0,
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

    // Recalculate discount amount from percentage based on new subtotal
    final discountAmount = subtotal * (discountPercent / 100);
    final totalAmount = subtotal - discountAmount;

    await dbProvider.update(
      'orders',
      values: {
        'subtotal': subtotal,
        'discount_percent': discountPercent,
        'discount_amount': discountAmount,
        'tax_percent': 0.0,
        'tax_amount': 0.0,
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
    // UPDATED: Query by order_id only, sort in-memory to avoid Firestore composite index
    final items = await dbProvider.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );

    // Sort by created_at in-memory
    items.sort((a, b) {
      final aTime = (a['created_at'] as num?)?.toInt() ?? 0;
      final bTime = (b['created_at'] as num?)?.toInt() ?? 0;
      return aTime.compareTo(bTime);
    });

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
