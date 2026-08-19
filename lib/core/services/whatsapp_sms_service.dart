import 'package:url_launcher/url_launcher.dart';
import '../utils/formatters.dart';

/// Optional WhatsApp / SMS notifications (spec: "Optional WhatsApp,
/// Optional SMS"). Uses the phone's own WhatsApp app / SMS app via native
/// share links - no messaging API keys or server needed, so the app stays
/// offline-first and this is purely a convenience the shop owner can ignore.
class WhatsAppSmsService {
    String _sanitizePhone(String phone) {
      var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 10) digits = '91$digits'; // default to India country code
      return digits;
    }

  Future<bool> sendWhatsApp({required String phone, required String message}) async {
    final number = _sanitizePhone(phone);
    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> sendSms({required String phone, required String message}) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
      );
    return launchUrl(uri);
  }

  String serviceStatusMessage({
    required String shopName,
    required String billNo,
    required String status,
    required String mobileName,
  }) {
    return '$shopName\nYour service $billNo ($mobileName) status: $status.\nThank you!';
  }

  /// Job-card intake intimation - sent automatically the moment a new
  /// service job card is created, using the shop's WhatsApp template.
  /// Opens WhatsApp (via wa.me, no API key) with the message pre-filled;
  /// the owner just taps Send inside WhatsApp.
  String serviceIntimationMessage({
    required String customerName,
    required String customerPhone,
    String? mobileModel,
    String? imei,
    String? complaint,
    String? workParts,
    double serviceCharge = 0,
    double sparePartsCharge = 0,
    required String status,
    required DateTime receivedDate,
    DateTime? expectedDelivery,
  }) {
    final total = serviceCharge + sparePartsCharge;
    String v(String? s) => (s == null || s.trim().isEmpty) ? '-' : s.trim();
    final work = v(workParts) == '-' ? 'To be updated after inspection' : v(workParts);
    return '📱 PROFESSIONAL MOBILES\n'
      '🔧 Mobile Service Intimation\n'
      'வணக்கம் 🙏 Dear Customer,\n'
      'உங்கள் mobile service-க்கு பெறப்பட்டுள்ளது.\n'
      '━━━━━━━━━━━━━━\n'
      '🧾 SERVICE DETAILS\n'
      '━━━━━━━━━━━━━━\n'
      '👤 Customer Name: $customerName\n'
      '📞 Mobile No: $customerPhone\n'
      '📱 Mobile Model: ${v(mobileModel)}\n'
      '🔢 IMEI No: ${v(imei)}\n'
      '🛠️ Service / Complaint:\n'
      '${v(complaint)}\n'
      '🔧 Work / Parts:\n'
      '$work\n'
      '💰 Service Charge: ${formatCurrency(serviceCharge)}\n'
      '🔩 Spare Parts Charge: ${formatCurrency(sparePartsCharge)}\n'
      '━━━━━━━━━━━━━━\n'
      '💵 TOTAL AMOUNT: ${formatCurrency(total)}\n'
      '━━━━━━━━━━━━━━\n'
      '📌 Service Status: $status\n'
      '📅 Received Date: ${formatDate(receivedDate)}\n'
      '📅 Expected Delivery: ${expectedDelivery != null ? formatDate(expectedDelivery) : '-'}\n'
      '⚠️ Note: Service முடிந்ததும் உங்களுக்கு WhatsApp மூலம் தகவல் தெரிவிக்கப்படும்.\n'
      '🙏 Thank you for choosing Professional Mobiles.\n'
      '📱 PROFESSIONAL MOBILES\n'
      'Trusted Mobile Service Center';
  }
}
