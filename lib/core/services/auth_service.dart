import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
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

  // Login session persistence. Previously `_current` only ever lived in
  // memory, so Android killing the app in the background (which is normal,
  // e.g. after tapping the Daily Orders widget) meant the PIN screen showed
  // again every single time even though the shop never "logged out". Stored
  // via home_widget's own local storage (same key space as the widget
  // on/off toggle) rather than the settings table, so a logged-in session
  // stays purely on-device and is never swept into a Google Drive/local
  // backup - restoring a backup on a new phone should never silently log
  // someone in.
  static const _sessionStaffIdKey = 'session_staff_id';

  Staff? _current;
  Staff? get current => _current;
  bool get isLoggedIn => _current != null;
  bool get isAdmin => _current?.isAdmin ?? false;

  /// Restores a previous login (if any) so the PIN screen is skipped.
  /// Called once on startup, after [hasAnyAccount] confirms an admin
  /// exists. Safe to call even with no saved session or a since-deleted/
  /// deactivated staff id - falls through to the normal PIN screen.
  Future<void> restoreSession() async {
    if (_current != null) return;
    final savedId = await HomeWidget.getWidgetData<String>(_sessionStaffIdKey);
    if (savedId == null || savedId.isEmpty) return;
    final staff = await _staffRepo.getById(savedId);
    if (staff != null) {
      _current = staff;
      notifyListeners();
    }
  }

  Future<void> _saveSession(String staffId) async {
    try {
      await HomeWidget.saveWidgetData<String>(_sessionStaffIdKey, staffId);
    } catch (_) {
      // Non-fatal - worst case the PIN is asked again next app open.
    }
  }

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

  // -----------------------------------------------------------------
  // Menu "section" access (Billing-only / Inventory-only / Full)
  // -----------------------------------------------------------------
  // Lets a shop hand staff a PIN that only ever shows Billing screens
  // (Sales/Service/2nd-Hand bills, printing, adding repair parts used) or
  // only ever shows Inventory screens (Spare Parts/Accessories/2nd-Hand
  // stock, Suppliers, Purchases) - Dashboard, Profit & Loss and Expenses
  // are never shown to either, and each section never sees the other's
  // screens. Admin and 'full' staff are unaffected (see everything, same
  // as before this existed).
  String get _section => isAdmin ? 'full' : (_current?.section ?? 'full');
  bool get isFullAccess => _section == 'full';
  bool get isBillingSection => _section == 'billing';
  bool get isInventorySection => _section == 'inventory';

  /// Screen ids a "Billing" login is allowed to open (must match the [id]
  /// values used in AppShell's destination list).
  static const _billingMenuIds = {'sales', 'services', 'second_hand'};

  /// Screen ids an "Inventory" login is allowed to open. Daily Orders lives
  /// here since it's a supplier-facing, stock-replenishment task, the same
  /// as Suppliers/Purchases.
  static const _inventoryMenuIds = {
    'spare_parts',
    'accessories',
    'second_hand',
    'suppliers',
    'purchases',
    'daily_orders',
  };

  /// Whether the current login's menu/drawer should include screen [id].
  /// Dashboard, Profit & Loss, Expenses, Customers and Settings are simply
  /// absent from both restricted sections' allow-lists, so they never show.
  bool canAccessMenu(String id) {
    if (isFullAccess) return true;
    if (isBillingSection) return _billingMenuIds.contains(id);
    if (isInventorySection) return _inventoryMenuIds.contains(id);
    return true;
  }

  /// Billing-side actions inside a shared screen (e.g. "Sell Phone" /
  /// "Print Sales Bill" on the 2nd-Hand Mobile detail screen, which also
  /// has Inventory-side actions like "Add Repair Cost" / "Change Status").
  bool get canDoBillingActions => isFullAccess || isBillingSection;

  /// Inventory-side actions inside a shared screen.
  bool get canDoInventoryActions => isFullAccess || isInventorySection;

  Future<bool> hasAnyAccount() => _staffRepo.hasAnyStaff();

  Future<Staff> setupFirstAdmin({required String name, required String pin, String? phone}) async {
    final admin = await _staffRepo.createAdmin(name: name, pin: pin, phone: phone);
    _current = admin;
    await _saveSession(admin.id);
    notifyListeners();
    return admin;
  }

  Future<bool> loginWithPin(String pin) async {
    final staff = await _staffRepo.verifyPin(pin);
    if (staff == null) return false;
    _current = staff;
    await _saveSession(staff.id);
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _current = null;
    await _saveSession('');
    notifyListeners();
  }
}
