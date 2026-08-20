import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../repositories/staff_repository.dart';
import '../../models/staff.dart';

/// Admin PIN gate + staff permissions (spec sections 28-29 / "Admin PIN,
/// Staff permissions" in the final requirement list). Kept as a
/// ChangeNotifier so the whole widget tree can react to login state and
/// hide profit/cost figures from anyone who isn't cleared to see them.
class AuthService extends ChangeNotifier {
  final _staffRepo = StaffRepository();

  // App-level access gate. This runs before the first-run admin setup so
  // that a copy of the APK alone is not enough to start using the app -
  // the shop's access password must be entered once per device first.
  static const String _appUnlockKey = 'app_access_unlocked';
  static const String _appAccessPassword = 'INRsr@@1434';

  bool _appUnlocked = false;
  bool get appUnlocked => _appUnlocked;

  Future<bool> loadAppUnlocked() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [_appUnlockKey]);
    _appUnlocked = rows.isNotEmpty && rows.first['value'] == '1';
    return _appUnlocked;
  }

  Future<bool> unlockApp(String password) async {
    if (password != _appAccessPassword) return false;
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'settings',
      {'key': _appUnlockKey, 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
      );
    _appUnlocked = true;
    notifyListeners();
    return true;
  }

  Staff? _current;
  Staff? get current => _current;
  bool get isLoggedIn => _current != null;
  bool get isAdmin => _current?.isAdmin ?? false;

  /// Admin/staff visibility rule used everywhere a bill or screen might
  /// leak internal cost/profit (spec section 28): customer-facing bills
  /// must NEVER show purchase cost, spare part cost, internal cost, profit,
  /// margin or supplier cost - only an authenticated admin/authorized staff
  /// member can see these on screen.
  bool get canSeeProfit => _current?.canViewProfit ?? false;
  bool get canSeeCost => _current?.canViewCost ?? false;

  /// Delete Records permission (spec: admin can grant a "Delete Records"
  /// permission to staff via the Staff/Employee permissions screen).
  /// Admins always have it implicitly.
  bool get canDelete => isAdmin || (_current?.canDeleteRecords ?? false);

  Future<bool> hasAnyAccount() => _staffRepo.hasAnyStaff();

  Future<Staff> setupFirstAdmin({required String name, required String pin, String? phone}) async {
    final admin = await _staffRepo.createAdmin(name: name, pin: pin, phone: phone);
    _current = admin;
    notifyListeners();
    return admin;
  }

  Future<bool> loginWithPin(String pin) async {
    final staff = await _staffRepo.verifyPin(pin);
    if (staff == null) return false;
    _current = staff;
    notifyListeners();
    return true;
  }

  void logout() {
    _current = null;
    notifyListeners();
  }
}
