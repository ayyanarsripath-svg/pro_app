import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/customer.dart';

class CustomerRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<Customer> create({
    required String name,
    String? phone,
    String? phone2,
    String? address,
    String? email,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final customer = Customer(
      id: newId(),
      name: name,
      phone: phone,
      phone2: phone2,
      address: address,
      email: email,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await db.insert('customers', customer.toMap());
    return customer;
  }

  Future<void> update(Customer customer) async {
    final db = await _dbHelper.database;
    await db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<List<Customer>> search(String query) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ? OR phone2 LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<List<Customer>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  /// Finds an existing customer by phone or creates a new one - used from
  /// quick-entry flows (service intake, sales bill) so the same customer
  /// isn't duplicated every visit.
  Future<Customer> findOrCreateByPhone({required String name, required String? phone}) async {
    if (phone != null && phone.trim().isNotEmpty) {
      final db = await _dbHelper.database;
      final rows = await db.query('customers', where: 'phone = ?', whereArgs: [phone.trim()]);
      if (rows.isNotEmpty) return Customer.fromMap(rows.first);
    }
    return create(name: name, phone: phone);
  }
}
