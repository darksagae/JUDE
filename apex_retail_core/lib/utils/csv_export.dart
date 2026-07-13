import 'dart:convert';
import 'dart:io';

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

/// Writes the CSV to a temp file and opens the platform share/save sheet so
/// the user can save it wherever they like (or open it straight in Excel).
Future<void> exportSalesCsv(List<Sale> sales, {String? filenamePrefix}) async {
  final csv = buildSalesCsv(sales);
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final file = File('${dir.path}/${filenamePrefix ?? 'sales_ledger'}_$stamp.csv');
  // A UTF-8 BOM so Excel (which otherwise guesses ANSI on some locales and
  // mangles non-ASCII text) opens the file as UTF-8 correctly.
  await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'text/csv')],
    fileNameOverrides: [file.uri.pathSegments.last],
  ));
}
