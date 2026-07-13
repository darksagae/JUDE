import 'package:intl/intl.dart';
import 'package:apex_retail_core/models/models.dart';

final NumberFormat _n = NumberFormat.decimalPattern('en_US');

/// Mirrors `.toLocaleString()` thousands grouping used throughout the web app.
String money(num v) => _n.format(v);

/// "shs 5,500"
String shs(num v) => 'shs ${_n.format(v)}';

bool isProductExpired(Product p, [DateTime? nowOverride]) {
  if (p.expirationDate == null || p.expirationDate!.isEmpty) return false;
  final exp = DateTime.tryParse(p.expirationDate!);
  if (exp == null) return false;
  final today = nowOverride ?? DateTime.now();
  return !exp.isAfter(DateTime(today.year, today.month, today.day));
}

bool isProductNearExpiry(Product p, [DateTime? nowOverride]) {
  if (p.expirationDate == null || p.expirationDate!.isEmpty) return false;
  final exp = DateTime.tryParse(p.expirationDate!);
  if (exp == null) return false;
  final today = nowOverride ?? DateTime.now();
  final days =
      exp.difference(DateTime(today.year, today.month, today.day)).inDays;
  return days >= 0 && days <= 7;
}

String fmtDateTime(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final local = d.toLocal();
  return DateFormat('MMM d, y  h:mm a').format(local);
}

String fmtTime(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('h:mm a').format(d.toLocal());
}

String fmtShortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('M/d/y').format(d.toLocal());
}

String paymentLabel(String method) {
  switch (method) {
    case 'cash':
      return 'Cash';
    case 'mobile_money':
      return 'Mobile Money';
    case 'card':
      return 'Bank Card';
    case 'partial':
      return 'Cash + Loan';
    default:
      return method;
  }
}

DateTime? saleLocalDay(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Filters sales by period: today, yesterday, week (last 7 days), month, all, custom.
bool saleMatchesPeriod(String iso, String period, [DateTime? customDay]) {
  final saleDay = saleLocalDay(iso);
  if (saleDay == null) return false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (period) {
    case 'today':
      return saleDay == today;
    case 'yesterday':
      return saleDay == today.subtract(const Duration(days: 1));
    case 'week':
      return !saleDay.isBefore(today.subtract(const Duration(days: 6)));
    case 'month':
      return saleDay.year == today.year && saleDay.month == today.month;
    case 'custom':
      if (customDay == null) return true;
      final cd = DateTime(customDay.year, customDay.month, customDay.day);
      return saleDay == cd;
    default:
      return true;
  }
}

String salesPeriodLabel(String period, DateTime? customDay) {
  switch (period) {
    case 'today':
      return 'Today';
    case 'yesterday':
      return 'Yesterday';
    case 'week':
      return 'Last 7 days';
    case 'month':
      return 'This month';
    case 'custom':
      if (customDay == null) return 'Pick a date';
      return DateFormat('MMM d, y').format(customDay);
    default:
      return 'All time';
  }
}
