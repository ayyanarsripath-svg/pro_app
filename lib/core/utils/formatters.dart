import 'package:intl/intl.dart';

final NumberFormat _rupee = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

final NumberFormat _rupeeDecimal = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

/// Formats a number as Indian Rupees, e.g. 125000 -> "₹1,25,000".
String formatCurrency(num value, {bool decimals = false}) {
  return decimals ? _rupeeDecimal.format(value) : _rupee.format(value);
}

/// Signed profit/loss display: positive shows "PROFIT ₹X", negative shows
/// "LOSS ₹X" (per spec section 7).
String formatProfitLoss(num value) {
  if (value < 0) {
    return 'LOSS ${formatCurrency(value.abs())}';
  }
  return 'PROFIT ${formatCurrency(value)}';
}

final DateFormat billDateFormat = DateFormat('dd/MM/yyyy');
final DateFormat billDateTimeFormat = DateFormat('dd/MM/yyyy  hh:mm a');
final DateFormat monthLabelFormat = DateFormat('MMMM yyyy');
final DateFormat isoDateFormat = DateFormat('yyyy-MM-dd');

String formatDate(DateTime d) => billDateFormat.format(d);
String formatDateTime(DateTime d) => billDateTimeFormat.format(d);
String formatMonthLabel(DateTime d) => monthLabelFormat.format(d);
