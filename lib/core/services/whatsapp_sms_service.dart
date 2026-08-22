import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/formatters.dart';

/// Optional WhatsApp / SMS notifications (spec: "Optional WhatsApp,
/// Optional SMS"). Uses the phone's own WhatsApp app / SMS app via native
/// share links - no messaging API keys or server needed, so the app stays
/// offline-first and this is purely a convenience the shop owner can ignore.
class WhatsAppSmsService {
  static const _shareChannel = MethodChannel('pro_app/whatsapp_share');

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

  /// One-click direct-to-WhatsApp file share (Daily Orders "send" button):
  /// opens WhatsApp itself with [filePath] (the order PDF) and [text] (the
  /// short caption) attached together in a single share, skipping
  /// Android's own "choose an app" chooser entirely (native side targets
  /// com.whatsapp directly - see MainActivity.kt). WhatsApp still shows its
  /// own contact/chat picker once opened; Android has no public API to
  /// pre-select a specific chat for a *file* share (only for plain wa.me
  /// text links, see [sendWhatsApp] above) - that one remaining tap is a
  /// WhatsApp/platform limitation, not something this app can remove.
  /// Returns false (rather than throwing) if WhatsApp isn't installed or
  /// anything about the native share fails, so callers can fall back to
  /// the older two-step [sendWhatsApp] + PDF-share flow.
  Future<bool> shareFileToWhatsApp({required String filePath, required String text}) async {
    try {
      final ok = await _shareChannel.invokeMethod<bool>('shareToWhatsApp', {
        'filePath': filePath,
        'text': text,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
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

  /// Delivery confirmation - sent the moment a job is marked Delivered from
  /// the Delivery Status action, once the final amount has been collected.
  String deliveryMessage({
    required String customerName,
    required String billNo,
    String? mobileName,
    required double totalAmount,
    required double paidAmount,
  }) {
    return '📱 PROFESSIONAL MOBILES\n'
      '✅ Delivery Confirmation\n'
      'வணக்கம் 🙏 Dear $customerName,\n'
      'Your device has been delivered.\n'
      '━━━━━━━━━━━━━━\n'
      '🧾 Bill No: $billNo\n'
      '📱 Mobile: ${mobileName ?? '-'}\n'
      '💰 Total Amount: ${formatCurrency(totalAmount)}\n'
      '✅ Paid: ${formatCurrency(paidAmount)}\n'
      '━━━━━━━━━━━━━━\n'
      '📌 Status: DELIVERED\n'
      '🙏 Thank you for choosing Professional Mobiles.\n'
      '📱 PROFESSIONAL MOBILES\n'
      'Trusted Mobile Service Center';
  }

  /// Daily supplier order (Daily Orders feature) - opens WhatsApp with just
  /// a short professional heading (spec: keep the chat text itself minimal
  /// - no supplier greeting, item count or dates here). Deliberately does
  /// NOT list phone numbers (those are for the shop's own in-app use only -
  /// see DailyOrderScreen) and does NOT list items either: the full
  /// itemised, date-wise list goes only in the attached PDF (see
  /// PdfService.buildDailyOrderPdf), sent as a separate share step right
  /// after this message, since a wa.me link can pre-fill text but can't
  /// carry a file attachment.
  String dailyOrderMessage({
    required String supplierName,
    required List<String> orderDateLabels,
    required int itemCount,
  }) {
    return 'Professional Mobiles Daily Order';
  }

  String warrantyClaimMessage({required String customerName, required String referenceLabel, required String description}) { return '''
      📱 PROFESSIONAL MOBILES
      🛡️ Warranty Claim Confirmation
      வணக்கம் 🙏 Dear Customer,
      Your warranty claim has been recorded.
      ━━━━━━━━━━━━━━
      👤 Customer Name: $customerName
      🧾 Reference: $referenceLabel
      📝 Issue: $description
      ━━━━━━━━━━━━━━
      ✅ Status: WARRANTY CLAIMED
      Our team will get in touch with you shortly regarding this claim.
      🙏 Thank you for choosing Professional Mobiles.
      📱 PROFESSIONAL MOBILES
      Trusted Mobile Service Center''';
  }
}
