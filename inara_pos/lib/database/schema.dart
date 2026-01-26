// Database Schema - SQL statements
// This file is loaded as a string resource

const String createTablesSQL = '''
-- Settings Table
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Roles Table (for custom role management)
CREATE TABLE IF NOT EXISTS roles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  description TEXT,
  permissions TEXT NOT NULL DEFAULT '[]', -- JSON array of section indices
  is_system_role INTEGER NOT NULL DEFAULT 0 CHECK(is_system_role IN (0, 1)), -- 1 for admin/cashier (cannot be deleted)
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Users Table (for PIN-based auth)
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  pin_hash TEXT NOT NULL,
  email TEXT,
  role TEXT NOT NULL, -- UPDATED: Can be any role name (admin, cashier, or custom roles)
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Categories Table
CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  is_locked INTEGER NOT NULL DEFAULT 0 CHECK(is_locked IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Products Table
CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  price REAL NOT NULL,
  cost REAL DEFAULT 0,
  image_url TEXT,
  is_veg INTEGER NOT NULL DEFAULT 1 CHECK(is_veg IN (0, 1)),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
  -- FIXED: Separate purchase items (raw materials) from menu items.
  -- Purchasable-only items must have is_sellable=0 so they never appear in Menu/Orders.
  is_purchasable INTEGER NOT NULL DEFAULT 0 CHECK(is_purchasable IN (0, 1)),
  is_sellable INTEGER NOT NULL DEFAULT 1 CHECK(is_sellable IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (category_id) REFERENCES categories(id)
);

-- Tables Table
CREATE TABLE IF NOT EXISTS tables (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_number TEXT UNIQUE NOT NULL,
  capacity INTEGER NOT NULL DEFAULT 4,
  status TEXT NOT NULL DEFAULT 'available' CHECK(status IN ('available', 'occupied')),
  row_position INTEGER,
  column_position INTEGER,
  position_label TEXT,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Orders Table (bill header)
CREATE TABLE IF NOT EXISTS orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_number TEXT UNIQUE NOT NULL,
  table_id INTEGER,
  order_type TEXT NOT NULL CHECK(order_type IN ('dine_in', 'takeaway')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'confirmed', 'completed', 'cancelled')),
  subtotal REAL NOT NULL DEFAULT 0,
  discount_amount REAL NOT NULL DEFAULT 0,
  discount_percent REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  tax_percent REAL NOT NULL DEFAULT 0,
  total_amount REAL NOT NULL DEFAULT 0,
  payment_method TEXT CHECK(payment_method IN ('cash', 'card', 'digital', 'credit')),
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK(payment_status IN ('unpaid', 'paid', 'partial')),
  customer_id INTEGER,
  credit_amount REAL NOT NULL DEFAULT 0,
  paid_amount REAL NOT NULL DEFAULT 0,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (table_id) REFERENCES tables(id),
  FOREIGN KEY (customer_id) REFERENCES customers(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Order Items Table (bill lines)
CREATE TABLE IF NOT EXISTS order_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL,
  product_id INTEGER NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  unit_price REAL NOT NULL,
  total_price REAL NOT NULL,
  notes TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id)
);

-- Payments Table
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  payment_method TEXT NOT NULL CHECK(payment_method IN ('cash', 'card', 'digital')),
  transaction_id TEXT,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Inventory Table
CREATE TABLE IF NOT EXISTS inventory (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL,
  quantity REAL NOT NULL DEFAULT 0,
  unit TEXT NOT NULL DEFAULT 'pcs',
  min_stock_level REAL NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (product_id) REFERENCES products(id)
);

-- Stock Transactions Table
CREATE TABLE IF NOT EXISTS stock_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL,
  transaction_type TEXT NOT NULL CHECK(transaction_type IN ('in', 'out', 'adjustment', 'sale')),
  quantity REAL NOT NULL,
  unit_price REAL DEFAULT 0,
  reference_type TEXT CHECK(reference_type IN ('purchase', 'sale', 'adjustment', 'manual')),
  reference_id INTEGER,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (product_id) REFERENCES products(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Inventory Ledger Table (ledger-based stock; used by InventoryLedgerService)
CREATE TABLE IF NOT EXISTS inventory_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL,
  product_name TEXT,
  unit TEXT NOT NULL DEFAULT 'pcs',
  quantity_in REAL NOT NULL DEFAULT 0,
  quantity_out REAL NOT NULL DEFAULT 0,
  unit_price REAL DEFAULT 0,
  transaction_type TEXT,
  reference_type TEXT,
  reference_id INTEGER,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (product_id) REFERENCES products(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Suppliers Table (vendors / parties)
CREATE TABLE IF NOT EXISTS suppliers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  notes TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Purchases Table
CREATE TABLE IF NOT EXISTS purchases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_number TEXT UNIQUE NOT NULL,
  bill_number TEXT,
  supplier_id INTEGER,
  supplier_name TEXT NOT NULL,
  total_amount REAL NOT NULL DEFAULT 0,
  discount_amount REAL NOT NULL DEFAULT 0,
  tax_amount REAL NOT NULL DEFAULT 0,
  paid_amount REAL NOT NULL DEFAULT 0,
  outstanding_amount REAL NOT NULL DEFAULT 0,
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK(payment_status IN ('unpaid', 'paid', 'partial')),
  status TEXT NOT NULL DEFAULT 'completed',
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Purchase Items Table
CREATE TABLE IF NOT EXISTS purchase_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_id INTEGER NOT NULL,
  product_id INTEGER NOT NULL,
  product_name TEXT,
  unit TEXT NOT NULL DEFAULT 'pcs',
  quantity REAL NOT NULL,
  unit_price REAL NOT NULL,
  total_price REAL NOT NULL,
  notes TEXT,
  FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id)
);

-- Purchase Payments Table (like customer payments)
CREATE TABLE IF NOT EXISTS purchase_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  purchase_id INTEGER NOT NULL,
  amount REAL NOT NULL,
  payment_method TEXT CHECK(payment_method IN ('cash', 'card', 'bank_transfer', 'other')),
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- In-house Expenses Table (non-supplier cash/bills like rent, salary, utilities)
CREATE TABLE IF NOT EXISTS expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  expense_number TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  category TEXT,
  amount REAL NOT NULL,
  payment_method TEXT CHECK(payment_method IN ('cash', 'card', 'bank_transfer', 'other')),
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Day Sessions Table (for day open/close)
CREATE TABLE IF NOT EXISTS day_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_date TEXT NOT NULL,
  opened_at INTEGER NOT NULL,
  closed_at INTEGER,
  opening_cash REAL NOT NULL DEFAULT 0,
  closing_cash REAL,
  total_sales REAL NOT NULL DEFAULT 0,
  total_cash REAL NOT NULL DEFAULT 0,
  total_card REAL NOT NULL DEFAULT 0,
  total_digital REAL NOT NULL DEFAULT 0,
  total_orders INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  opened_by INTEGER,
  closed_by INTEGER,
  is_closed INTEGER NOT NULL DEFAULT 0 CHECK(is_closed IN (0, 1)),
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (opened_by) REFERENCES users(id),
  FOREIGN KEY (closed_by) REFERENCES users(id)
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id INTEGER,
  user_id INTEGER,
  old_value TEXT,
  new_value TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Customers Table
CREATE TABLE IF NOT EXISTS customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  credit_limit REAL NOT NULL DEFAULT 0,
  credit_balance REAL NOT NULL DEFAULT 0,
  notes TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Credit Transactions Table
CREATE TABLE IF NOT EXISTS credit_transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  order_id INTEGER,
  transaction_type TEXT NOT NULL CHECK(transaction_type IN ('credit', 'payment', 'adjustment')),
  amount REAL NOT NULL,
  balance_before REAL NOT NULL,
  balance_after REAL NOT NULL,
  notes TEXT,
  created_by INTEGER,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  FOREIGN KEY (customer_id) REFERENCES customers(id),
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (created_by) REFERENCES users(id)
);

-- Sync Queue Table (for Firestore sync)
CREATE TABLE IF NOT EXISTS sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  operation TEXT NOT NULL CHECK(operation IN ('create', 'update', 'delete')),
  data TEXT,
  created_at INTEGER NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0 CHECK(synced IN (0, 1)),
  sync_attempts INTEGER NOT NULL DEFAULT 0
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_synced ON orders(synced);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_synced ON payments(synced);
CREATE INDEX IF NOT EXISTS idx_stock_transactions_product_id ON stock_transactions(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_transactions_synced ON stock_transactions(synced);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_synced ON inventory_ledger(synced);
CREATE INDEX IF NOT EXISTS idx_purchases_synced ON purchases(synced);
CREATE INDEX IF NOT EXISTS idx_day_sessions_session_date ON day_sessions(session_date);
CREATE INDEX IF NOT EXISTS idx_sync_queue_synced ON sync_queue(synced);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_customer_id ON credit_transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_synced ON credit_transactions(synced);
''';
