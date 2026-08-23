import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Single source of truth for the offline SQLite database used across the
/// whole app. No server, no network dependency - everything lives in one
/// local .db file that can be backed up / restored (see BackupService).
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;
  static const int dbVersion = 6;
  static const String dbFileName = 'professional_mobiles.db';

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<String> databaseFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, dbFileName);
  }

  Future<Database> _initDb() async {
    final path = await databaseFilePath();
    return openDatabase(
      path,
      version: dbVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) { await db.execute('ALTER TABLE services ADD COLUMN fault_amounts TEXT'); }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE services ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE second_hand_phones ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
    }
    // Staff "section" (Billing-only / Inventory-only / Full) - restricts
    // which menu screens a staff PIN can even see, on top of the existing
    // per-field permissions. Defaults to 'full' so every staff account
    // created before this update keeps seeing everything it already could.
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE staff ADD COLUMN section TEXT NOT NULL DEFAULT 'full'");
    }
    // Daily Orders feature (daily supplier order note - see
    // DailyOrderScreen / DailyOrderRepository). Phone is stored here for
    // the shop's own in-app reference (tap to call) only - it must never
    // be printed/sent outside the app.
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE daily_order_items (
          id TEXT PRIMARY KEY,
          order_date TEXT NOT NULL,
          s_no INTEGER NOT NULL,
          part_name TEXT NOT NULL,
          type_model TEXT,
          quantity TEXT NOT NULL,
          phone TEXT,
          sent INTEGER NOT NULL DEFAULT 0,
          sent_at TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_daily_order_items_date ON daily_order_items(order_date)');
      await db.execute('CREATE INDEX idx_daily_order_items_sent ON daily_order_items(sent)');
    }
    // Bargain/write-off discount on Service Bills and 2nd Hand Sales
    // (e.g. total 100, customer pays 90, remaining 10 marked as a
    // discount instead of sitting as a pending balance) - see
    // ServiceJob.discount / SecondHandSale.discount. Sales Bill soft
    // delete (active flag, same pattern as services/second_hand_phones).
    // device_type on second_hand_phones distinguishes Mobile vs Laptop so
    // the same purchase/sale/warranty flow serves both (Laptop Sales).
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE services ADD COLUMN discount REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE second_hand_sales ADD COLUMN discount REAL NOT NULL DEFAULT 0');
      await db.execute("ALTER TABLE second_hand_phones ADD COLUMN device_type TEXT NOT NULL DEFAULT 'mobile'");
      await db.execute('ALTER TABLE sales_bills ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ---------------------------------------------------------------
    // Core / Identity
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    batch.execute('''
      CREATE TABLE staff (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        pin_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff', -- admin | staff
        section TEXT NOT NULL DEFAULT 'full', -- full | billing | inventory
        can_view_profit INTEGER NOT NULL DEFAULT 0,
        can_view_cost INTEGER NOT NULL DEFAULT 0,
        can_edit_prices INTEGER NOT NULL DEFAULT 0,
        can_manage_expenses INTEGER NOT NULL DEFAULT 0,
        can_manage_inventory INTEGER NOT NULL DEFAULT 1,
        can_delete_records INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        phone2 TEXT,
        address TEXT,
        email TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_customers_phone ON customers(phone)');

    // ---------------------------------------------------------------
    // Suppliers / Purchases
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        purchase_no TEXT,
        supplier_id TEXT,
        purchase_date TEXT NOT NULL,
        category TEXT NOT NULL, -- spare_part | accessory | other
        total_amount REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE purchase_items (
        id TEXT PRIMARY KEY,
        purchase_id TEXT NOT NULL,
        item_type TEXT NOT NULL, -- spare_part | accessory
        item_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_cost REAL NOT NULL,
        total_cost REAL NOT NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE
      )
    ''');

    // ---------------------------------------------------------------
    // Spare Parts inventory
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE spare_parts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT,
        compatible_model TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        current_stock REAL NOT NULL DEFAULT 0,
        avg_purchase_cost REAL NOT NULL DEFAULT 0,
        low_stock_threshold REAL NOT NULL DEFAULT 2,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE spare_part_transactions (
        id TEXT PRIMARY KEY,
        spare_part_id TEXT NOT NULL,
        txn_type TEXT NOT NULL, -- purchase | service_usage | adjustment | supplier_return | second_hand_usage
        quantity REAL NOT NULL, -- positive = stock in, negative = stock out
        unit_cost REAL NOT NULL DEFAULT 0,
        reference_type TEXT,
        reference_id TEXT,
        txn_date TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (spare_part_id) REFERENCES spare_parts(id)
      )
    ''');

    // ---------------------------------------------------------------
    // Accessories inventory + sales
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE accessories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT,
        brand TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        current_stock REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        selling_price REAL NOT NULL DEFAULT 0,
        low_stock_threshold REAL NOT NULL DEFAULT 3,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE accessory_transactions (
        id TEXT PRIMARY KEY,
        accessory_id TEXT NOT NULL,
        txn_type TEXT NOT NULL, -- purchase | sale | sales_return | stock_return | adjustment
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        reference_type TEXT,
        reference_id TEXT,
        txn_date TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (accessory_id) REFERENCES accessories(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE sales_bills (
        id TEXT PRIMARY KEY,
        bill_no TEXT NOT NULL,
        bill_type TEXT NOT NULL DEFAULT 'accessory', -- accessory | other
        customer_id TEXT,
        sale_date TEXT NOT NULL,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        paid REAL NOT NULL DEFAULT 0,
        balance REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        notes TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    batch.execute('''
      CREATE TABLE sales_bill_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        accessory_id TEXT,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        rate REAL NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales_bills(id) ON DELETE CASCADE
      )
    ''');

    // ---------------------------------------------------------------
    // Services (job cards / repair bills)
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE services (
        id TEXT PRIMARY KEY,
        bill_no TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        mobile_name TEXT,
        model TEXT,
        imei TEXT,
        complaint TEXT, fault_amounts TEXT,
        device_condition TEXT,
        existing_damage TEXT,
        acc_charger INTEGER NOT NULL DEFAULT 0,
        acc_cable INTEGER NOT NULL DEFAULT 0,
        acc_sim INTEGER NOT NULL DEFAULT 0,
        acc_memory_card INTEGER NOT NULL DEFAULT 0,
        acc_other TEXT,
        technician TEXT,
        status TEXT NOT NULL DEFAULT 'Received',
        labour_cost REAL NOT NULL DEFAULT 0,
        warranty INTEGER NOT NULL DEFAULT 0,
        warranty_period TEXT,
        estimated_amount REAL NOT NULL DEFAULT 0,
        final_amount REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        advance REAL NOT NULL DEFAULT 0,
        paid REAL NOT NULL DEFAULT 0,
        balance REAL NOT NULL DEFAULT 0,
        expected_date TEXT,
        actual_date TEXT,
        delivery_person TEXT,
        delivery_status TEXT NOT NULL DEFAULT 'Pending',
        additional_expense REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_services_status ON services(status)');
    batch.execute('CREATE INDEX idx_services_customer ON services(customer_id)');

    batch.execute('''
      CREATE TABLE service_status_history (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        status TEXT NOT NULL,
        changed_at TEXT NOT NULL,
        changed_by TEXT,
        notes TEXT,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE service_photos (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        photo_path TEXT NOT NULL,
        caption TEXT,
        taken_at TEXT NOT NULL,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE service_spare_parts (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        spare_part_id TEXT,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit_cost REAL NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE service_other_costs (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE service_payments (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT,
        paid_at TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE warranty_claims (
        id TEXT PRIMARY KEY,
        claim_type TEXT NOT NULL, -- service | second_hand | accessory
        reference_id TEXT NOT NULL,
        claim_date TEXT NOT NULL,
        description TEXT,
        resolution TEXT,
        cost REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Open',
        created_at TEXT NOT NULL
      )
    ''');

    // ---------------------------------------------------------------
    // 2nd Hand Mobile module
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE second_hand_phones (
        id TEXT PRIMARY KEY,
        purchase_no TEXT NOT NULL,
        purchase_date TEXT NOT NULL,
        device_type TEXT NOT NULL DEFAULT 'mobile', -- mobile | laptop
        seller_name TEXT,
        seller_phone TEXT,
        brand TEXT,
        model TEXT,
        imei1 TEXT,
        imei2 TEXT,
        ram TEXT,
        storage TEXT,
        colour TEXT,
        condition_grade TEXT,
        battery_health TEXT,
        display_condition TEXT,
        body_condition TEXT,
        accessories_received TEXT,
        purchase_price REAL NOT NULL DEFAULT 0,
        other_cost REAL NOT NULL DEFAULT 0,
        expected_selling_price REAL NOT NULL DEFAULT 0,
        actual_selling_price REAL,
        sale_date TEXT,
        customer_id TEXT,
        warranty INTEGER NOT NULL DEFAULT 0,
        warranty_period TEXT,
        notes TEXT,
        photo_path TEXT,
        status TEXT NOT NULL DEFAULT 'Purchased', -- Purchased|Repairing|Ready for Sale|Sold|Returned|Reserved
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    batch.execute('CREATE INDEX idx_shp_status ON second_hand_phones(status)');

    batch.execute('''
      CREATE TABLE second_hand_repair_items (
        id TEXT PRIMARY KEY,
        phone_id TEXT NOT NULL,
        description TEXT NOT NULL,
        spare_part_id TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        cost REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (phone_id) REFERENCES second_hand_phones(id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE second_hand_sales (
        id TEXT PRIMARY KEY,
        phone_id TEXT NOT NULL,
        bill_no TEXT NOT NULL,
        customer_id TEXT,
        sale_date TEXT NOT NULL,
        sale_price REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        paid REAL NOT NULL DEFAULT 0,
        balance REAL NOT NULL DEFAULT 0,
        warranty INTEGER NOT NULL DEFAULT 0,
        warranty_period TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (phone_id) REFERENCES second_hand_phones(id),
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // ---------------------------------------------------------------
    // Expenses
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        expense_date TEXT NOT NULL,
        category TEXT NOT NULL, -- Rent, Electricity, Internet, Transport, Salary, Tools, Consumables, Packaging, Courier, Misc...
        amount REAL NOT NULL,
        payment_method TEXT,
        description TEXT,
        allocation TEXT NOT NULL DEFAULT 'general', -- general | service | accessories | second_hand | other
        created_at TEXT NOT NULL
      )
    ''');

    // ---------------------------------------------------------------
    // Returns
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE returns (
        id TEXT PRIMARY KEY,
        return_type TEXT NOT NULL, -- accessory_sales_return | accessory_stock_return | second_hand_customer_return | spare_part_supplier_return
        reference_type TEXT,
        reference_id TEXT,
        item_name TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        amount REAL NOT NULL DEFAULT 0,
        reason TEXT,
        return_date TEXT NOT NULL,
        refund_method TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ---------------------------------------------------------------
    // Unified accounting ledger - THE source of truth for all P&L math.
    // Every purchase / sale / service-part-usage / return / adjustment /
    // expense writes one or more rows here (transaction-based accounting,
    // never derived from "sales minus current stock").
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE ledger_transactions (
        id TEXT PRIMARY KEY,
        txn_date TEXT NOT NULL,
        category TEXT NOT NULL, -- service | accessories | spare_parts | second_hand | other | expense
        txn_type TEXT NOT NULL, -- revenue | direct_cost | expense | investment | refund | return
        reference_type TEXT,
        reference_id TEXT,
        amount REAL NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_ledger_date ON ledger_transactions(txn_date)');
    batch.execute('CREATE INDEX idx_ledger_category ON ledger_transactions(category)');

    // ---------------------------------------------------------------
    // Backups
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE backups (
        id TEXT PRIMARY KEY,
        backup_date TEXT NOT NULL,
        type TEXT NOT NULL, -- manual | weekly_auto | google_drive
        file_path TEXT,
        status TEXT NOT NULL DEFAULT 'success',
        notes TEXT
      )
    ''');

    // ---------------------------------------------------------------
    // Daily Orders (daily supplier order note - see DailyOrderScreen)
    // ---------------------------------------------------------------
    batch.execute('''
      CREATE TABLE daily_order_items (
        id TEXT PRIMARY KEY,
        order_date TEXT NOT NULL,
        s_no INTEGER NOT NULL,
        part_name TEXT NOT NULL,
        type_model TEXT,
        quantity TEXT NOT NULL,
        phone TEXT,
        sent INTEGER NOT NULL DEFAULT 0,
        sent_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_daily_order_items_date ON daily_order_items(order_date)');
    batch.execute('CREATE INDEX idx_daily_order_items_sent ON daily_order_items(sent)');

    await batch.commit(noResult: true);
  }

  Future<void> closeDb() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  /// Full path to the live database file - used by BackupService for
  /// manual export / Google Drive upload / weekly auto-backup.
  Future<File> dbFile() async => File(await databaseFilePath());
}
