import 'package:flutter/foundation.dart';

import '../repositories/staff_repository.dart';
import '../../models/staff.dart';

/// Admin PIN gate + staff permissions (spec sections 28-29 / "Admin PIN,
/// Staff permissions" in the final requirement list). Kept as a
/// ChangeNotifier so the whole widget tree can react to login state and
/// hide profit/cost figures from anyone who isn't cleared to see them.
class AuthService extends ChangeNotifier {
  final _staffRepo = StaffRepository();

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
