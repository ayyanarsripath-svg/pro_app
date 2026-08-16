import 'package:url_launcher/url_launcher.dart';

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

  String serviceReadyMessage({
    required String shopName,
    required String billNo,
    required double balance,
  }) {
    final balanceLine = balance > 0
        ? '\nBalance due: ₹${balance.toStringAsFixed(0)}'
        : '';
    return '$shopName\nYour device ($billNo) is ready for pickup!$balanceLine';
  }
}
