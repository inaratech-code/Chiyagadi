# Purchase + Inventory Module

## Overview

This module implements a **ledger-based inventory system** where stock is **NEVER stored directly** but is **always calculated** from inventory ledger entries. This ensures data integrity and provides a complete audit trail.

## Key Principles

1. **Stock is Calculated, Not Stored**
   - Current Stock = Sum(quantityIn) - Sum(quantityOut)
   - Stock is calculated in real-time from ledger entries
   - No direct stock editing allowed

2. **Purchases Cannot Be Deleted**
   - Data integrity requirement
   - For corrections, use reverse inventory ledger entries

3. **Automatic Ledger Updates**
   - Every purchase automatically creates ledger entries
   - Every sale automatically creates ledger entries
   - Complete audit trail maintained

## File Structure

### Models (`lib/models/`)
- `supplier_model.dart` - Supplier/vendor model
- `purchase_model.dart` - Purchase order model
- `purchase_item_model.dart` - Purchase line item model
- `inventory_ledger_model.dart` - Inventory ledger entry model

### Services (`lib/services/`)
- `supplier_service.dart` - Supplier CRUD operations
- `purchase_service.dart` - Purchase creation with automatic ledger updates
- `inventory_ledger_service.dart` - Stock calculation and ledger management

### Screens (`lib/screens/`)
- `purchases/new_purchase_screen.dart` - New purchase creation screen
- `inventory/inventory_ledger_screen.dart` - Inventory view with ledger-based stock

## Firestore Collections

The following collections are used:

1. **suppliers** - Supplier information
   - Fields: name, contact_person, phone, email, address, notes, is_active, created_at, updated_at

2. **purchases** - Purchase orders
   - Fields: supplier_id, supplier_name, purchase_number, total_amount, discount_amount, tax_amount, notes, status, created_by, created_at, updated_at

3. **purchase_items** - Purchase line items
   - Fields: purchase_id, product_id, product_name, quantity, unit_price, total_price, notes

4. **inventory_ledger** - Inventory transaction ledger
   - Fields: product_id, product_name, quantity_in, quantity_out, unit_price, transaction_type, reference_type, reference_id, notes, created_by, created_at

## Usage

### Creating a Purchase

```dart
final purchaseService = PurchaseService();

await purchaseService.createPurchase(
  context: context,
  supplierId: supplierId,
  supplierName: supplierName,
  items: purchaseItems,
  discountAmount: discountAmount,
  taxAmount: taxAmount,
  notes: notes,
);
```

This automatically:
1. Creates the purchase record
2. Creates purchase items
3. Creates inventory ledger entries (quantityIn = purchased quantity)
4. Updates product costs (average cost method)

### Getting Current Stock

```dart
final ledgerService = InventoryLedgerService();

// Single product
final stock = await ledgerService.getCurrentStock(
  context: context,
  productId: productId,
);

// Multiple products (batch)
final stockMap = await ledgerService.getCurrentStockBatch(
  context: context,
  productIds: productIds,
);
```

### Viewing Ledger History

```dart
final history = await ledgerService.getLedgerHistory(
  context: context,
  productId: productId,
  limit: 50,
);
```

## Stock Calculation Formula

```
Current Stock = Sum(quantityIn) - Sum(quantityOut)
```

Where:
- `quantityIn` = Stock increases (from purchases, adjustments, returns)
- `quantityOut` = Stock decreases (from sales, adjustments, corrections)

## Transaction Types

- `purchase` - Stock increase from purchase
- `sale` - Stock decrease from sale
- `adjustment` - Manual stock adjustment
- `return` - Stock return
- `correction` - Reverse entry for corrections

## Offline Support

All operations use Firestore offline persistence:
- Purchases can be created while offline
- Ledger entries are queued and synced automatically
- Stock calculations work with cached data

## Safety Features

1. **No Purchase Deletion** - Purchases cannot be deleted to maintain data integrity
2. **Reverse Entries** - Use `createReverseEntry()` for corrections
3. **Transaction Safety** - All operations use database transactions
4. **Audit Trail** - Complete history maintained in ledger

## Integration with Existing Code

The module is designed to work alongside existing code:
- Uses existing `UnifiedDatabaseProvider` for database access
- Compatible with existing `Product` model
- Works with both SQLite (mobile) and Firestore (web)
- Supports offline persistence

## Next Steps

To fully integrate:
1. Update existing purchase screen to use `NewPurchaseScreen` or integrate the service
2. Update existing inventory screen to use `InventoryLedgerScreen` or integrate the service
3. Ensure database schema includes the new collections (already added to Firestore provider)
4. Test purchase creation and stock calculations

## Notes

- Stock is always calculated in real-time - no caching needed
- Product costs are updated using average cost method
- All operations are transactional for data integrity
- The module follows the existing codebase patterns and conventions
