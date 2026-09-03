/// One row of the Spare Parts usage log (spec item 2: "main menu list la
/// expenses erukkula athula spare part list need na service bill la add
/// part la choose panra ella spare parts um ethula list aaganum price bill
/// number mobile name model eppadi oru order la erukka details ellam fill
/// panni" - a full audit trail of exactly what spare part was used on
/// which Service Bill, for how much, so the shop can see precisely what's
/// being counted into Profit & Loss).
///
/// Built entirely from data that already existed - every "Add Part" on a
/// Service Bill already calls SparePartRepository.useForService, which logs
/// a spare_part_transactions row (txn_type 'service_usage') at that part's
/// average cost, linked to the exact service via reference_id. This is
/// simply that same trail, joined with the spare part's name and the
/// service's bill/mobile/model, read-only.
class SparePartUsage {
  final String id;
  final String partName;
  final String? category;
  final String billNo;
  final String? mobileName;
  final String? model;
  final double quantity;
  final double unitCost;
  final DateTime date;

  SparePartUsage({
    required this.id,
    required this.partName,
    this.category,
    required this.billNo,
    this.mobileName,
    this.model,
    required this.quantity,
    required this.unitCost,
    required this.date,
  });

  double get totalCost => quantity * unitCost;

  factory SparePartUsage.fromMap(Map<String, dynamic> m) => SparePartUsage(
        id: m['id'] as String,
        partName: m['part_name'] as String,
        category: m['part_category'] as String?,
        billNo: m['bill_no'] as String? ?? '-',
        mobileName: m['mobile_name'] as String?,
        model: m['model'] as String?,
        // Stored negative (stock going OUT) in spare_part_transactions -
        // flipped here since this is a usage/cost log, not a stock ledger.
        quantity: -((m['quantity'] as num).toDouble()),
        unitCost: (m['unit_cost'] as num).toDouble(),
        date: DateTime.parse(m['txn_date'] as String),
      );
}
