import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../repositories/settings_repository.dart';
import '../utils/formatters.dart';

/// Optional WhatsApp / SMS notifications (spec: "Optional WhatsApp,
/// Optional SMS"). Uses the phone's own WhatsApp app / SMS app via native
/// share links - no messaging API keys or server needed, so the app stays
/// offline-first and this is purely a convenience the shop owner can ignore.
class WhatsAppSmsService {
  static const _shareChannel = MethodChannel('pro_app/whatsapp_share');
  final _settingsRepo = SettingsRepository();

  // Android package names for the two WhatsApp variants - see
  // Settings -> WhatsApp Sending / SettingsRepository.whatsappSendApp.
  static const _businessPackage = 'com.whatsapp.w4b';
  static const _regularPackage = 'com.whatsapp';

  String _sanitizePhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits'; // default to India country code
    return digits;
  }

  Future<bool> sendWhatsApp({required String phone, required String message}) async {
    final number = _sanitizePhone(phone);
    final url = 'https://wa.me/$number?text=${Uri.encodeComponent(message)}';

    // A shop that replies to customers from WhatsApp Business (not the
    // regular consumer WhatsApp app) was finding intimations quietly
    // opening in whichever app Android/the phone's "open by default"
    // setting happened to pick - often the *other* one, which they don't
    // watch, so it read as "the message never went out" even though it
    // technically opened somewhere. When the shop has explicitly chosen
    // an app in Settings -> WhatsApp Sending, target it directly here;
    // 'auto' (the default, unset) falls through to the exact previous
    // behaviour, unchanged.
    final preferred = await _settingsRepo.getWhatsAppSendApp();
    if (Platform.isAndroid && preferred != 'auto') {
      final targetPackage = preferred == 'business' ? _businessPackage : _regularPackage;
      try {
        final intent = AndroidIntent(action: 'action_view', data: url, package: targetPackage);
        await intent.launch();
        return true;
      } catch (_) {
        // That specific app isn't installed on this phone, or launching it
        // failed for any other reason - fall through to the plain generic
        // link below instead of leaving the shop with nothing sent.
      }
    }

    final uri = Uri.parse(url);
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
  ///
  /// Also respects Settings -> WhatsApp Sending (same
  /// [SettingsRepository.getWhatsAppSendApp] choice [sendWhatsApp] above
  /// already honoured) - previously this specific PDF-attach flow ignored
  /// that setting entirely and always targeted regular WhatsApp on the
  /// native side, so a shop that chose "Business" there still saw the Daily
  /// Order Send button open regular WhatsApp every time (spec: "daily order
  /// send panrathu normal whatsapp than open aaguthu enakku business
  /// whtsapp open aaganum athukku option set pannu").
  Future<bool> shareFileToWhatsApp({required String filePath, required String text, String? phone}) async {
    try {
      final preferred = await _settingsRepo.getWhatsAppSendApp();
      final targetPackage = preferred == 'business'
          ? _businessPackage
          : preferred == 'regular'
              ? _regularPackage
              : null; // 'auto' - let the native side use its own default (com.whatsapp)
      final ok = await _shareChannel.invokeMethod<bool>('shareToWhatsApp', {
        'filePath': filePath,
        'text': text,
        'phone': (phone == null || phone.trim().isEmpty) ? null : _sanitizePhone(phone),
        'targetPackage': targetPackage,
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
  /// Uses the shop's own saved "Received" template (see
  /// WhatsAppTemplateScreen / SettingsRepository) when one has been
  /// customized, substituting {customerName}/{mobileName}/{complaint}/
  /// {amount}/{shopName} tokens - falls back to the original built-in
  /// wording when no custom template is saved yet.
  Future<String> serviceIntimationMessage({
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
  }) async {
    final total = serviceCharge + sparePartsCharge;
    String v(String? s) => (s == null || s.trim().isEmpty) ? '-' : s.trim();
    final shopName = (await _settingsRepo.get(SettingsRepository.shopName))?.trim();
    final resolvedShopName = (shopName == null || shopName.isEmpty) ? 'PROFESSIONAL MOBILES' : shopName;
    final custom = await _settingsRepo.getReceivedIntimationTemplate();
    if (custom != null && custom.trim().isNotEmpty) {
      var text = custom;
      text = text.replaceAll('{customerName}', customerName);
      text = text.replaceAll('{mobileName}', v(mobileModel));
      text = text.replaceAll('{complaint}', v(complaint));
      text = text.replaceAll('{amount}', formatCurrency(total));
      text = text.replaceAll('{shopName}', resolvedShopName);
      return text;
    }
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
  /// Uses the shop's own saved "Delivery" template (see
  /// WhatsAppTemplateScreen / SettingsRepository) when one has been
  /// customized, substituting {customerName}/{mobileName}/{amount}/
  /// {paidAmount}/{billNo}/{shopName} tokens - falls back to the original
  /// built-in wording when no custom template is saved yet.
  Future<String> deliveryMessage({
    required String customerName,
    required String billNo,
    String? mobileName,
    required double totalAmount,
    required double paidAmount,
  }) async {
    final shopName = (await _settingsRepo.get(SettingsRepository.shopName))?.trim();
    final resolvedShopName = (shopName == null || shopName.isEmpty) ? 'PROFESSIONAL MOBILES' : shopName;
    final custom = await _settingsRepo.getDeliveryIntimationTemplate();
    if (custom != null && custom.trim().isNotEmpty) {
      var text = custom;
      text = text.replaceAll('{customerName}', customerName);
      text = text.replaceAll('{mobileName}', mobileName ?? '-');
      text = text.replaceAll('{amount}', formatCurrency(totalAmount));
      text = text.replaceAll('{paidAmount}', formatCurrency(paidAmount));
      text = text.replaceAll('{billNo}', billNo);
      text = text.replaceAll('{shopName}', resolvedShopName);
      return text;
    }
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
  /// once the phone is actually handed back. Uses the shop's own saved
  /// template (see WhatsAppTemplateScreen / SettingsRepository) when one has
  /// been customized, substituting {customerName}/{mobileName}/{amount}/
  /// {billNo}/{shopName} tokens - falls back to the original built-in
  /// wording when no custom template is saved yet.
  Future<String> readyForDeliveryMessage({
    required String customerName,
    String? mobileName,
    required double amount,
    required String billNo,
  }) async {
    final modelLabel = (mobileName ?? '').trim();
    final shopName = (await _settingsRepo.get(SettingsRepository.shopName))?.trim();
    final resolvedShopName = (shopName == null || shopName.isEmpty) ? 'PROFESSIONAL MOBILES' : shopName;
    final custom = await _settingsRepo.getReadyIntimationTemplate();
    if (custom != null && custom.trim().isNotEmpty) {
      var text = custom;
      text = text.replaceAll('{customerName}', customerName);
      text = text.replaceAll('{mobileName}', modelLabel.isEmpty ? 'மொபைல்' : modelLabel);
      text = text.replaceAll('{amount}', formatCurrency(amount));
      text = text.replaceAll('{billNo}', billNo);
      text = text.replaceAll('{shopName}', resolvedShopName);
      return text;
    }
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
  /// Uses the shop's own saved Daily Order caption template (see
  /// WhatsAppTemplateScreen / SettingsRepository, editable from Daily
  /// Orders' own Settings dialog) when one has been customized, substituting
  /// {supplierName}/{itemCount}/{dates}/{shopName} tokens - falls back to
  /// the original short built-in heading when no custom template is saved
  /// yet (spec: "more ... whatspp app message customize panra option need
  /// and preview kattanum").
  Future<String> dailyOrderMessage({
    required String supplierName,
    required List<String> orderDateLabels,
    required int itemCount,
  }) async {
    final shopName = (await _settingsRepo.get(SettingsRepository.shopName))?.trim();
    final resolvedShopName = (shopName == null || shopName.isEmpty) ? 'PROFESSIONAL MOBILES' : shopName;
    final custom = await _settingsRepo.getDailyOrderMessageTemplate();
    if (custom != null && custom.trim().isNotEmpty) {
      var text = custom;
      text = text.replaceAll('{supplierName}', supplierName);
      text = text.replaceAll('{itemCount}', itemCount.toString());
      text = text.replaceAll('{dates}', orderDateLabels.join(', '));
      text = text.replaceAll('{shopName}', resolvedShopName);
      return text;
    }
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
