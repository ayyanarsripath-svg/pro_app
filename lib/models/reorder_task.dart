/// A quick supplier "order note" with a scheduled auto-send time.
///
/// Flow (per the shop owner's spec):
///  1. Quick-note what needs to be ordered (the "widget").
///  2. Pick/enter the supplier name + phone number.
///  3. Set the time it should go out.
///  4. At that time the app raises a reminder notification and prepares the
///     order PDF; tapping the notification opens the ready-to-send WhatsApp
///     share sheet - the owner only has to tap Send inside WhatsApp.
class ReorderTask {
  final String id;
  final String note;
  final String? supplierId;
  final String supplierName;
  final String supplierPhone;
  final DateTime scheduledAt;
  final bool repeatDaily;
  final String status; // pending | notified | sent | cancelled
  final String? pdfPath;
  final int notificationId;
  final DateTime createdAt;

  ReorderTask({
    required this.id,
    required this.note,
    this.supplierId,
    required this.supplierName,
    required this.supplierPhone,
    required this.scheduledAt,
    this.repeatDaily = false,
    this.status = 'pending',
    this.pdfPath,
    required this.notificationId,
    required this.createdAt,
  });

  static const statusPending = 'pending';
  static const statusNotified = 'notified';
  static const statusSent = 'sent';
  static const statusCancelled = 'cancelled';

  ReorderTask copyWith({
    String? status,
    String? pdfPath,
    DateTime? scheduledAt,
  }) {
    return ReorderTask(
      id: id,
      note: note,
      supplierId: supplierId,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      repeatDaily: repeatDaily,
      status: status ?? this.status,
      pdfPath: pdfPath ?? this.pdfPath,
      notificationId: notificationId,
      createdAt: createdAt,
    );
  }

  factory ReorderTask.fromMap(Map<String, dynamic> m) => ReorderTask(
        id: m['id'] as String,
        note: m['note'] as String,
        supplierId: m['supplier_id'] as String?,
        supplierName: m['supplier_name'] as String,
        supplierPhone: m['supplier_phone'] as String,
        scheduledAt: DateTime.parse(m['scheduled_at'] as String),
        repeatDaily: (m['repeat_daily'] as int? ?? 0) == 1,
        status: m['status'] as String? ?? statusPending,
        pdfPath: m['pdf_path'] as String?,
        notificationId: m['notification_id'] as int,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'note': note,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'supplier_phone': supplierPhone,
        'scheduled_at': scheduledAt.toIso8601String(),
        'repeat_daily': repeatDaily ? 1 : 0,
        'status': status,
        'pdf_path': pdfPath,
        'notification_id': notificationId,
        'created_at': createdAt.toIso8601String(),
      };
}
