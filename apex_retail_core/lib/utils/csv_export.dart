import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/utils/format.dart';

/// Escapes a field for CSV per RFC 4180: wrap in quotes and double up any
/// embedded quotes whenever the value contains a comma, quote, or newline.
String _csvField(Object? v) {
  final s = '$v';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String _csvRow(List<Object?> fields) => fields.map(_csvField).join(',');

/// Builds a CSV of the given sales — one row per transaction — openable
/// directly in Excel/Sheets. Includes profit, so callers should only pass
/// this to Manager/Top Manager, matching the ledger's own visibility rule.
String buildSalesCsv(List<Sale> sales) {
  final buf = StringBuffer();
  buf.writeln(_csvRow([
    'Sale ID',
    'Date/Time',
    'Cashier ID',
    'Cashier Name',
    'Items',
    'Payment Method',
    'Total Amount',
    'Amount Paid',
    'Change Due',
    'Loan Amount',
    'Customer Name',
    'Payment Due By',
    'Total Profit',
  ]));
  for (final s in sales) {
    final items = s.items
        .map((it) => '${it.productName} x${it.quantity}')
        .join('; ');
    buf.writeln(_csvRow([
      s.id,
      fmtDateTime(s.timestamp),
      s.cashierId,
      s.cashierName,
      items,
      paymentLabel(s.paymentMethod),
      s.totalAmount,
      s.amountPaid,
      s.changeDue,
      s.loanAmount,
      s.customerName ?? '',
      s.loanPledgeDate ?? '',
      s.totalProfit,
    ]));
  }
  return buf.toString();
}

/// Exports the sales as a CSV. On mobile (Android/iOS) this opens the platform
/// share sheet. On desktop (Linux/Windows/macOS) — where share_plus has no
/// registered plugin and would throw — it writes the file into the user's
/// Downloads folder and returns the saved path so the caller can show it.
///
/// Returns the absolute file path when saved to disk (desktop), or null when
/// the file was handed off via the share sheet (mobile).
Future<String?> exportSalesCsv(List<Sale> sales, {String? filenamePrefix}) async {
  final csv = buildSalesCsv(sales);
  // A UTF-8 BOM so Excel (which otherwise guesses ANSI on some locales and
  // mangles non-ASCII text) opens the file as UTF-8 correctly.
  final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final filename = '${filenamePrefix ?? 'sales_ledger'}_$stamp.csv';

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  if (isMobile) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      fileNameOverrides: [filename],
    ));
    return null;
  }

  // Desktop: save straight to Downloads (fall back to Documents, then temp) and
  // report the path — no share sheet exists on these platforms.
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  return file.path;
}
