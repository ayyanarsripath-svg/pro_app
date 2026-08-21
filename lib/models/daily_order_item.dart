/// One row of a Daily Order note (Daily Orders feature) - a part or
/// accessory the shop needs to order from its supplier. [orderDate] is the
/// day this row was originally noted down (yyyy-MM-dd) - it stays fixed
/// even if the row later gets carried forward into a later day's send
/// (see DailyOrderRepository.unsentItems), which is exactly what lets the
/// printed order note show "which day each item was noted on" even when
/// several unsent days end up combined into one send.
///
/// [phone] is deliberately never included in anything sent outside the
/// app (PDF, WhatsApp message) - it's for the shop's own in-app reference
/// only (tap to call).
class DailyOrderItem {
  final String id;
  final String orderDate;
  final int sNo;
  final String partName;
  final String? typeModel;
  final String quantity;
  final String? phone;
  final bool sent;
  final DateTime? sentAt;
  final DateTime createdAt;

  DailyOrderItem({
    required this.id,
    required this.orderDate,
    required this.sNo,
    required this.partName,
    this.typeModel,
    required this.quantity,
    this.phone,
    this.sent = false,
    this.sentAt,
    required this.createdAt,
  });

  DailyOrderItem copyWith({bool? sent, DateTime? sentAt}) => DailyOrderItem(
        id: id,
        orderDate: orderDate,
        sNo: sNo,
        partName: partName,
        typeModel: typeModel,
        quantity: quantity,
        phone: phone,
        sent: sent ?? this.sent,
        sentAt: sentAt ?? this.sentAt,
        createdAt: createdAt,
      );

  factory DailyOrderItem.fromMap(Map<String, dynamic> m) => DailyOrderItem(
        id: m['id'] as String,
        orderDate: m['order_date'] as String,
        sNo: m['s_no'] as int,
        partName: m['part_name'] as String,
        typeModel: m['type_model'] as String?,
        quantity: m['quantity'] as String,
        phone: m['phone'] as String?,
        sent: (m['sent'] as int) == 1,
        sentAt: m['sent_at'] != null ? DateTime.parse(m['sent_at'] as String) : null,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_date': orderDate,
        's_no': sNo,
        'part_name': partName,
        'type_model': typeModel,
        'quantity': quantity,
        'phone': phone,
        'sent': sent ? 1 : 0,
        'sent_at': sentAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
