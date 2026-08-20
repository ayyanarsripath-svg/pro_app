import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/staff.dart';

String hashPin(String pin) => sha256.convert(utf8.encode('pms-salt::$pin')).toString();

class StaffRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<bool> hasAnyStaff() async {
    final db = await _dbHelper.database;
    final rows = await db.query('staff', limit: 1);
    return rows.isNotEmpty;
  }

  /// Creates the first Admin account (used on first app launch).
  Future<Staff> createAdmin({required String name, required String pin, String? phone}) async {
    final db = await _dbHelper.database;
    final staff = Staff(
      id: newId(),
      name: name,
      phone: phone,
      pinHash: hashPin(pin),
      role: 'admin',
      section: 'full',
      canViewProfit: true,
      canViewCost: true,
      canEditPrices: true,
      canManageExpenses: true,
      canManageInventory: true,
      canDeleteRecords: true,
      createdAt: DateTime.now(),
    );
    await db.insert('staff', staff.toMap());
    return staff;
  }

  Future<Staff> createStaff({
    required String name,
    required String pin,
    String? phone,
    String section = 'full',
    bool canViewProfit = false,
    bool canViewCost = false,
    bool canEditPrices = false,
    bool canManageExpenses = false,
    bool canManageInventory = true,
    bool canDeleteRecords = false,
  }) async {
    final db = await _dbHelper.database;
    final staff = Staff(
      id: newId(),
      name: name,
      phone: phone,
      pinHash: hashPin(pin),
      role: 'staff',
      section: section,
      canViewProfit: canViewProfit,
      canViewCost: canViewCost,
      canEditPrices: canEditPrices,
      canManageExpenses: canManageExpenses,
      canManageInventory: canManageInventory,
      canDeleteRecords: canDeleteRecords,
      createdAt: DateTime.now(),
    );
    await db.insert('staff', staff.toMap());
    return staff;
  }

  Future<void> update(Staff staff) async {
    final db = await _dbHelper.database;
    await db.update('staff', staff.toMap(), where: 'id = ?', whereArgs: [staff.id]);
  }

  Future<Staff?> verifyPin(String pin) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'staff',
      where: 'pin_hash = ? AND active = 1',
      whereArgs: [hashPin(pin)],
    );
    if (rows.isEmpty) return null;
    return Staff.fromMap(rows.first);
  }

  Future<List<Staff>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('staff', orderBy: 'created_at');
    return rows.map(Staff.fromMap).toList();
  }

  Future<void> setActive(String id, bool active) async {
    final db = await _dbHelper.database;
    await db.update('staff', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }
}
