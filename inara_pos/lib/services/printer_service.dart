import 'package:flutter/foundation.dart';
import '../providers/unified_database_provider.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../utils/number_formatter.dart';

class PrinterService {
  final OrderService _orderService = OrderService();

  // Print bill
  Future<void> printBill(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    final order = await _orderService.getOrderById(dbProvider, orderId);
    if (order == null) {
      throw Exception('Order not found');
    }

    final items = await _orderService.getOrderItems(dbProvider, orderId);

    // Get café settings
    final cafeName = await _getSetting(dbProvider, 'cafe_name', 'Inara Café');
    final cafeAddress = await _getSetting(dbProvider, 'cafe_address', '');
    final cafePhone = await _getSetting(dbProvider, 'cafe_phone', '');

    // Generate bill text
    final billText =
        _generateBillText(order, items, cafeName, cafeAddress, cafePhone);

    // Print using ESC/POS
    // In real implementation, use esc_pos_bluetooth or esc_pos_utils
    debugPrint('BILL PRINT:\n$billText');

    // TODO: Implement actual printer connection and printing
    // This is a placeholder - implement using esc_pos_bluetooth or network printer
  }

  // Print KOT (Kitchen Order Ticket)
  Future<void> printKOT(
      UnifiedDatabaseProvider dbProvider, dynamic orderId) async {
    final order = await _orderService.getOrderById(dbProvider, orderId);
    if (order == null) {
      throw Exception('Order not found');
    }

    final items = await _orderService.getOrderItems(dbProvider, orderId);

    // Get café settings
    final cafeName = await _getSetting(dbProvider, 'cafe_name', 'Inara Café');

    // Generate KOT text
    final kotText = _generateKOTText(order, items, cafeName);

    // Print using ESC/POS
    debugPrint('KOT PRINT:\n$kotText');

    // TODO: Implement actual printer connection and printing
  }

  String _generateBillText(Order order, List<Map<String, dynamic>> items,
      String cafeName, String cafeAddress, String cafePhone) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('=' * 42);
    buffer.writeln(cafeName.toUpperCase().padLeft((42 + cafeName.length) ~/ 2));
    if (cafeAddress.isNotEmpty) {
      buffer.writeln(cafeAddress.padLeft((42 + cafeAddress.length) ~/ 2));
    }
    if (cafePhone.isNotEmpty) {
      buffer
          .writeln('Tel: $cafePhone'.padLeft((42 + cafePhone.length + 4) ~/ 2));
    }
    buffer.writeln('=' * 42);
    buffer.writeln();

    // Order info
    buffer.writeln('Order: ${order.orderNumber}');
    buffer.writeln('Date: ${_formatDateTime(order.createdAt)}');
    buffer.writeln(
        'Type: ${order.orderType == 'dine_in' ? 'Dine-In' : 'Takeaway'}');
    if (order.tableId != null) {
      buffer.writeln('Table: ${order.tableId}');
    }
    buffer.writeln('-' * 42);
    buffer.writeln();

    // Items
    buffer.writeln('Items:');
    for (final item in items) {
      final quantity = item['quantity'] as int? ?? 1;
      final productName = item['product_name'] as String? ??
          _getProductName(item['product_id']);
      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final totalPrice = (item['total_price'] as num?)?.toDouble() ?? 0.0;
      final notes = item['notes'] as String?;

      buffer.writeln('$quantity x $productName');
      buffer.writeln('  ${NumberFormatter.formatCurrency(unitPrice)}');
      buffer.writeln('  ${NumberFormatter.formatCurrency(totalPrice)}');
      if (notes != null && notes.isNotEmpty) {
        buffer.writeln('  Note: $notes');
      }
      buffer.writeln();
    }

    buffer.writeln('-' * 42);

    // Totals
    buffer.writeln(
        'Subtotal:     ${NumberFormatter.formatCurrency(order.subtotal).padLeft(20)}');
    if (order.discountAmount > 0) {
      buffer.writeln(
          'Discount:     ${NumberFormatter.formatCurrency(-order.discountAmount).padLeft(20)}');
    }
    buffer.writeln('=' * 42);
    buffer.writeln(
        'TOTAL:        ${NumberFormatter.formatCurrency(order.totalAmount).padLeft(20)}');
    buffer.writeln('=' * 42);
    buffer.writeln();

    // Payment
    if (order.paymentMethod != null) {
      buffer.writeln('Payment: ${order.paymentMethod!.toUpperCase()}');
      buffer.writeln(
          'Amount:  ${NumberFormatter.formatCurrency(order.totalAmount)}');
    }
    buffer.writeln();
    buffer.writeln('Thank you for visiting!');
    buffer.writeln('=' * 42);

    return buffer.toString();
  }

  String _generateKOTText(
      Order order, List<Map<String, dynamic>> items, String cafeName) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('=' * 42);
    buffer.writeln('KITCHEN ORDER TICKET');
    buffer.writeln(cafeName.toUpperCase().padLeft((42 + cafeName.length) ~/ 2));
    buffer.writeln('=' * 42);
    buffer.writeln();

    // Order info
    buffer.writeln('Order: ${order.orderNumber}');
    buffer.writeln('Time: ${_formatTime(order.createdAt)}');
    buffer.writeln(
        'Type: ${order.orderType == 'dine_in' ? 'Dine-In' : 'Takeaway'}');
    if (order.tableId != null) {
      buffer.writeln('Table: ${order.tableId}');
    }
    buffer.writeln('-' * 42);
    buffer.writeln();

    // Items
    for (final item in items) {
      final quantity = item['quantity'] as int? ?? 1;
      final productName = item['product_name'] as String? ??
          _getProductName(item['product_id']);
      final notes = item['notes'] as String?;

      buffer.writeln('$quantity x $productName');
      if (notes != null && notes.isNotEmpty) {
        buffer.writeln('  Note: $notes');
      }
      buffer.writeln();
    }

    buffer.writeln('=' * 42);

    return buffer.toString();
  }

  String _formatDateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getProductName(int productId) {
    // In real implementation, load product name from database
    // For now, return placeholder
    return 'Product $productId';
  }

  Future<String> _getSetting(UnifiedDatabaseProvider dbProvider, String key,
      String defaultValue) async {
    try {
      await dbProvider.init();
      final settings = await dbProvider.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );

      if (settings.isNotEmpty) {
        return settings.first['value'] as String;
      }
    } catch (e) {
      debugPrint('Error getting setting $key: $e');
    }

    return defaultValue;
  }
}
