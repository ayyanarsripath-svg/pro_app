import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends a file (the order PDF) toward a specific supplier over WhatsApp.
///
/// Important, honest limitation: Android/WhatsApp does not allow any app to
/// both (a) pre-attach a file AND (b) pre-select exactly which WhatsApp
/// chat it goes to, in one automated step - Meta blocks that combination
/// deliberately. So this offers the two building blocks the owner actually
/// asked for and lets them land on Send in at most two taps:
///   1. [openChat] opens WhatsApp straight to the supplier's chat (correct
///      recipient, pre-filled text) using the phone number - no picking a
///      contact needed.
///   2. [sharePdf] opens Android's share sheet with the order PDF already
///      attached - the owner taps the WhatsApp icon (and, if the number
///      isn't already a saved contact, that same chat) and taps Send.
class WhatsAppFileService {
  String _sanitizePhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits'; // default to India country code
    return digits;
  }

  Future<bool> openChat({required String phone, required String message}) async {
    final number = _sanitizePhone(phone);
    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> sharePdf({required String pdfPath, required String supplierName, String? caption}) async {
    await Share.shareXFiles(
      [XFile(pdfPath, mimeType: 'application/pdf')],
      text: caption,
      subject: 'Order for $supplierName',
    );
  }
}
