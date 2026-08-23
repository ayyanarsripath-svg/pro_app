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
  /// com.whatsapp directly - see MainActivity.kt).
  ///
  /// When [phone] is given, the native side also passes WhatsApp an extra
  /// ("jid") that opens straight into that specific contact's chat with
  /// the file already attached - just one tap on Send inside WhatsApp, no
  /// contact/chat picker. This isn't an official WhatsApp API (there's no
  /// public one for pre-selecting a chat on a *file* share), but it's a
  /// long-standing, widely-used technique that works reliably on current
  /// WhatsApp - if a future WhatsApp update ever stops honouring it,
  /// WhatsApp simply falls back to its own picker, never worse than
  /// before.
  /// Returns false (rather than throwing) if WhatsApp isn't installed or
  /// anything about the native share fails, so callers can fall back to
  /// the older two-step [sendWhatsApp] + PDF-share flow.
  Future<bool> shareFileToWhatsApp({required String filePath, required String text, String? phone}) async {
    try {
      final ok = await _shareChannel.invokeMethod<bool>('shareToWhatsApp', {
        'filePath': filePath,
        'text': text,
        'phone': (phone == null || phone.trim().isEmpty) ? null : _sanitizePhone(phone),
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
  /// the owner just taps Send inside WhatsApp. Deliberately kept short
  /// (spec: simplify - just model, problem and the combined amount) -
  /// full details (IMEI, work/parts breakdown, dates, status) stay
  /// available inside the app itself, not in the WhatsApp text. Unused
  /// params (customerPhone, imei, workParts, status, receivedDate,
  /// expectedDelivery) are kept so every call site stays unchanged.
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
    return '📱 Mobile Service Received\n'
      'Dear Customer, உங்கள் mobile service-க்கு கொடுக்கப்பட்டுள்ளது.\n'
      '🔧 Model: ${v(mobileModel)}\n'
      '📝 Problem: ${v(complaint)}\n'
      '💰 spare + service charge Amount: ${formatCurrency(total)}\n'
      '📞 Service முடிந்ததும் உங்களுக்கு WhatsApp மூலம் தகவல் தெரிவிக்கப்படும். நன்றி! 🙏\n'
      'professional mobiles trusted service\n'
      'ma.kunnathur';
  }

  /// Delivery confirmation - sent the moment a job is marked Delivered from
  /// the Delivery Status action, once the final amount has been collected.
  /// Simplified to match serviceIntimationMessage's short style (spec:
  /// simplify the WhatsApp text) - bill no / status stay in the app itself.
  String deliveryMessage({
    required String customerName,
    required String billNo,
    String? mobileName,
    required double totalAmount,
    required double paidAmount,
  }) {
    return '📱 Mobile Service Delivered\n'
      'Dear Customer, உங்கள் mobile service முடிந்து ஒப்படைக்கப்பட்டுள்ளது.\n'
      '🔧 Model: ${mobileName ?? '-'}\n'
      '💰 Total Amount: ${formatCurrency(totalAmount)}\n'
      '✅ Paid: ${formatCurrency(paidAmount)}\n'
      '🙏 நன்றி! Thank you for choosing Professional Mobiles.\n'
      'professional mobiles trusted service\n'
      'ma.kunnathur';
  }

  /// "Ready for delivery" notice - sent the moment a service job's status
  /// is changed to Ready (see ServiceStatus.ready / ServiceDetailScreen's
  /// _changeStatus), distinct from [deliveryMessage] which fires later,
  /// once the phone is actually handed back. Uses the shop's exact given
  /// template.
  String readyForDeliveryMessage({
    required String customerName,
    String? mobileName,
    required double amount,
    required String billNo,
  }) {
    final modelLabel = (mobileName ?? '').trim();
    return '📱 PROFESSIONAL MOBILES\n'
      'வணக்கம் $customerName அவர்களே! 👋\n'
      'உங்களுடைய ${modelLabel.isEmpty ? 'மொபைல்' : modelLabel} மொபைல் service செய்து முடிக்கப்பட்டுவிட்டது. ✅\n'
      '📦 Mobile Delivery-ku Ready!\n'
      '💰 Service Amount: ${formatCurrency(amount)}\n'
      '🧾 Bill No: $billNo\n'
      'தயவுசெய்து கடைக்கு வந்து உங்கள் mobile-ஐ பெற்றுக்கொள்ளவும்.\n'
      '🙏 நன்றி\n'
      'PROFESSIONAL MOBILES';
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
