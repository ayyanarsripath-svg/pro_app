class Staff {
  final String id;
  final String name;
  final String? phone;
  final String pinHash;
  final String role; // admin | staff

  /// Which menu screens this login can even see, on top of the finer
  /// per-field permissions below - lets a shop hand out a "Billing" PIN
  /// (Sales/Service/2nd-Hand bills + printing only) or an "Inventory" PIN
  /// (Spare Parts/Accessories/2nd-Hand stock + Suppliers/Purchases only)
  /// without either one ever seeing the Dashboard, Profit & Loss, Expenses,
  /// or the other section's screens. 'full' (the default) keeps the
  /// original behaviour where a staff PIN can see every screen, subject
  /// only to the permission checkboxes.
  final String section; // full | billing | inventory
  final bool canViewProfit;
  final bool canViewCost;
  final bool canEditPrices;
  final bool canManageExpenses;
  final bool canManageInventory;
  final bool canDeleteRecords;
  final bool active;
  final DateTime createdAt;

  Staff({
    required this.id,
    required this.name,
    this.phone,
    required this.pinHash,
    this.role = 'staff',
    this.section = 'full',
    this.canViewProfit = false,
    this.canViewCost = false,
    this.canEditPrices = false,
    this.canManageExpenses = false,
    this.canManageInventory = true,
    this.canDeleteRecords = false,
    this.active = true,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isBillingSection => section == 'billing';
  bool get isInventorySection => section == 'inventory';
  bool get isFullSection => section == 'full';

  factory Staff.fromMap(Map<String, dynamic> m) => Staff(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        pinHash: m['pin_hash'] as String,
        role: m['role'] as String? ?? 'staff',
        section: m['section'] as String? ?? 'full',
        canViewProfit: (m['can_view_profit'] as int? ?? 0) == 1,
        canViewCost: (m['can_view_cost'] as int? ?? 0) == 1,
        canEditPrices: (m['can_edit_prices'] as int? ?? 0) == 1,
        canManageExpenses: (m['can_manage_expenses'] as int? ?? 0) == 1,
        canManageInventory: (m['can_manage_inventory'] as int? ?? 1) == 1,
        canDeleteRecords: (m['can_delete_records'] as int? ?? 0) == 1,
        active: (m['active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'pin_hash': pinHash,
        'role': role,
        'section': section,
        'can_view_profit': canViewProfit ? 1 : 0,
        'can_view_cost': canViewCost ? 1 : 0,
        'can_edit_prices': canEditPrices ? 1 : 0,
        'can_manage_expenses': canManageExpenses ? 1 : 0,
        'can_manage_inventory': canManageInventory ? 1 : 0,
        'can_delete_records': canDeleteRecords ? 1 : 0,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };
}
