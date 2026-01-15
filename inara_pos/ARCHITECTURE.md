# InaraPOS Architecture

## System Overview

InaraPOS is an **offline-first** POS system designed for small cafés in Nepal. The system prioritizes local data storage and operation, with optional cloud backup via Firebase Firestore.

## Core Principles

1. **Offline-First**: All critical operations work without internet
2. **SQLite Primary**: SQLite is the single source of truth
3. **Firestore Backup**: Firestore only syncs finalized data in background
4. **Non-Blocking**: Firestore sync never blocks billing or printing
5. **Simple UX**: Minimal taps, clear totals, confident payments

## Architecture Layers

### 1. Presentation Layer
- **Flutter Widgets**: Material Design 3
- **Theme**: Dark theme for POS, light theme for admin
- **State Management**: Provider pattern
- **Navigation**: Named routes + Material navigation

### 2. Business Logic Layer
- **Services**: OrderService, PrinterService, SyncService
- **Providers**: AuthProvider, DatabaseProvider, SyncProvider
- **Business Rules**: Tax calculation, discounts, inventory deduction

### 3. Data Layer
- **Primary Database**: SQLite (sqflite)
- **Backup Database**: Firebase Firestore
- **Local Storage**: SharedPreferences (settings, PIN)
- **Models**: Dart classes with toMap/fromMap

### 4. Infrastructure Layer
- **Network**: Connectivity detection
- **Printing**: ESC/POS (Bluetooth + Network)
- **Authentication**: PIN-based (SHA-256 hashed)
- **Sync**: Background queue-based sync

## Database Schema

### Core Tables

1. **users**: PIN-based authentication
2. **categories**: Product categories
3. **products**: Menu items
4. **tables**: Table management
5. **orders**: Bill headers
6. **order_items**: Bill line items
7. **payments**: Payment records
8. **inventory**: Stock levels
9. **stock_transactions**: Inventory movements
10. **purchases**: Purchase orders
11. **purchase_items**: Purchase line items
12. **day_sessions**: Day open/close
13. **settings**: App configuration
14. **audit_log**: Change tracking
15. **sync_queue**: Firestore sync queue

### Sync Strategy

- **Unsynced Flag**: `synced = 0` for unsynced records
- **Sync Queue**: Background sync processes unsynced records
- **Sync Entities**: orders, payments, purchases, stock_transactions, day_sessions
- **Never Overwrite**: SQLite timestamps always win
- **Background Only**: Sync runs when online, never blocks operations

## Data Flow

### Billing Flow

```
User selects items → Cart updated → Order created (SQLite)
→ Payment confirmed → Order finalized → Sync queued (Firestore)
→ Inventory deducted → Bill printed → KOT printed
```

### Sync Flow

```
Record created/updated → synced = 0 → Background sync checks
→ If online → Push to Firestore → Update synced = 1
→ If offline → Keep synced = 0 → Retry when online
```

## Module Status

### ✅ Completed Modules

1. **Authentication**: PIN-based login, roles, auto-lock
2. **Database**: SQLite schema, models, provider
3. **POS Screen**: Billing interface (basic structure)
4. **Order Service**: Order creation, item management, payment
5. **Sync Service**: Firestore background sync
6. **Printer Service**: Bill/KOT formatting (structure)
7. **Theme**: Dark POS theme, light admin theme

### 🚧 Partially Complete

1. **POS Screen**: Core structure done, needs product loading
2. **Printer Service**: Formatting done, needs actual printer connection
3. **Sync Service**: Logic done, needs testing

### 📋 Pending Modules

1. **Table Management**: Table grid, status, assignment
2. **Menu Management**: Product CRUD, categories
3. **Inventory Management**: Stock levels, alerts, adjustments
4. **Purchase Management**: Supplier, purchase entry
5. **Sales & Day Closing**: Sales list, day open/close
6. **Reports**: Daily sales, item-wise, CSV export
7. **Settings**: Configuration UI
8. **Backup & Restore**: Export/import functionality

## Technology Stack

### Frontend
- **Framework**: Flutter 3.0+
- **Language**: Dart 3.0+
- **State Management**: Provider
- **UI**: Material Design 3

### Backend
- **Primary DB**: SQLite (sqflite)
- **Backup DB**: Firebase Firestore
- **Authentication**: PIN (SHA-256)

### Printing
- **Protocol**: ESC/POS
- **Transport**: Bluetooth (Android), Network (Android + iOS)

### Deployment
- **Android**: Native APK
- **iOS**: Progressive Web App (PWA)

## File Structure

```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models
│   ├── category.dart
│   ├── product.dart
│   ├── order.dart
│   ├── order_item.dart
│   └── table.dart
├── providers/                   # State management
│   ├── auth_provider.dart
│   ├── database_provider.dart
│   └── sync_provider.dart
├── screens/                     # UI screens
│   ├── auth/
│   ├── home/
│   ├── pos/
│   ├── menu/
│   ├── tables/
│   ├── sales/
│   ├── reports/
│   ├── inventory/
│   ├── purchases/
│   └── settings/
├── services/                    # Business logic
│   ├── order_service.dart
│   └── printer_service.dart
├── database/                    # Database schema
│   ├── schema.dart
│   └── schema.sql
└── utils/                       # Utilities
    ├── theme.dart
    └── number_formatter.dart
```

## Security

### Authentication
- PIN hashed with SHA-256
- Stored in SQLite users table
- Session-based (in-memory)
- Auto-lock after 5 minutes inactivity

### Data Protection
- Local data encrypted (recommended for production)
- Firestore security rules
- Audit log for critical changes
- No admin keys in APK

### Sync Security
- Only finalized data synced
- Owner-only write (if multi-user)
- Timestamp validation
- No overwrites from Firestore

## Performance Considerations

### Offline Performance
- All queries to SQLite (local, fast)
- No network waits for billing
- Async operations don't block UI

### Sync Performance
- Batch sync operations
- Background sync only
- Retry with exponential backoff
- Sync queue limits

### UI Performance
- Lazy loading for lists
- Pagination for large datasets
- Image caching
- Efficient rebuilds (Provider)

## Future Enhancements

1. **Multi-Outlet Support**: Expand to multiple cafés
2. **Online Ordering**: Customer-facing ordering
3. **Analytics Dashboard**: Advanced reporting
4. **Integration APIs**: Payment gateways, accounting
5. **Mobile App for Customers**: Order tracking
6. **Advanced Inventory**: Recipes, BOM, cost tracking
7. **Employee Management**: Shift tracking, commissions
8. **Loyalty Program**: Points, rewards

## Deployment Checklist

- [x] Flutter project structure
- [x] Database schema
- [x] Core models
- [x] Authentication
- [x] POS screen structure
- [x] Order service
- [x] Sync service structure
- [x] Printer service structure
- [x] Android configuration
- [x] Web/PWA configuration
- [x] Documentation
- [ ] Complete all screens
- [ ] Complete printer integration
- [ ] Testing
- [ ] Performance optimization
- [ ] Security audit
- [ ] Production build

## Notes

- **Production Ready**: Core structure is production-ready
- **Modules**: Several modules are placeholders (need implementation)
- **Testing**: Unit tests and integration tests needed
- **Documentation**: User manual needed
- **Localization**: English only (Nepali can be added)
