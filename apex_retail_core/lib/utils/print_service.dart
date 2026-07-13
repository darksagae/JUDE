import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode/barcode.dart' as bc;

import 'package:apex_retail_core/branding.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/utils/format.dart';

/// Generates and prints thermal-style receipts and barcode stickers as PDFs.
/// Uses the `printing` plugin which supports Windows desktop and Android/iOS.
class PrintService {
  static double _widthMm(PrinterSettings s) =>
      s.paperWidth == '80mm' ? 80 : 58;

  static Future<void> printReceipt(Sale sale, PrinterSettings settings) async {
    final doc = await _buildReceipt(sale, settings);
    await Printing.layoutPdf(onLayout: (_) async => doc);
  }

  static Future<void> shareReceipt(Sale sale, PrinterSettings settings) async {
    final doc = await _buildReceipt(sale, settings);
    await Printing.sharePdf(bytes: doc, filename: 'receipt_${sale.id}.pdf');
  }

  static Future<Uint8List> _buildReceipt(
      Sale sale, PrinterSettings settings) async {
    final pdf = pw.Document();
    final w = _widthMm(settings);
    final pageFormat =
        PdfPageFormat(w * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm);

    pw.Widget divider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
            children: List.generate(
                40,
                (_) => pw.Expanded(
                    child: pw.Text('-',
                        style: const pw.TextStyle(fontSize: 6))))));

    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k,
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(v,
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ]);

    pdf.addPage(pw.Page(
      pageFormat: pageFormat,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Center(
              child: pw.Text(AppBranding.receiptHeader,
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold))),
          pw.Center(
              child: pw.Text('Plot 12, Kampala Plaza Rd',
                  style: const pw.TextStyle(fontSize: 7))),
          pw.Center(
              child: pw.Text('Tel: +256 702 345 678',
                  style: const pw.TextStyle(fontSize: 7))),
          divider(),
          pw.Text('SALE ID: ${sale.id}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text('Date/Time: ${fmtDateTime(sale.timestamp)}',
              style: const pw.TextStyle(fontSize: 7)),
          pw.Text('Cashier: ${sale.cashierName} (${sale.cashierId})',
              style: const pw.TextStyle(fontSize: 7)),
          divider(),
          pw.Row(children: [
            pw.Expanded(
                flex: 3,
                child: pw.Text('ITEM',
                    style: pw.TextStyle(
                        fontSize: 7, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(
                child: pw.Text('QTY',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 7, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(
                flex: 2,
                child: pw.Text('TOTAL',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 7, fontWeight: pw.FontWeight.bold))),
          ]),
          divider(),
          ...sale.items.map((it) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Row(children: [
                      pw.Expanded(
                          flex: 3,
                          child: pw.Text(it.productName,
                              style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(
                          child: pw.Text('x${it.quantity}',
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 8))),
                      pw.Expanded(
                          flex: 2,
                          child: pw.Text(money(it.totalSellingPrice),
                              textAlign: pw.TextAlign.right,
                              style: const pw.TextStyle(fontSize: 8))),
                    ]),
                    pw.Text(
                        '@ ${money(it.sellingPrice)} / unit'
                        '${it.isWholesale ? ' (WHOLESALE)' : ''}',
                        style: const pw.TextStyle(
                            fontSize: 6, color: PdfColors.grey600)),
                  ]))),
          divider(),
          kv('SUBTOTAL:', shs(sale.totalAmount)),
          kv('TOTAL:', shs(sale.totalAmount), bold: true),
          divider(),
          kv('PAY METHOD:', sale.paymentMethod.replaceAll('_', ' ').toUpperCase()),
          if (sale.paymentMethod == 'mobile_money' &&
              sale.mobileMoneyTxId != null)
            kv('REF TXID:', sale.mobileMoneyTxId!),
          kv('CASH PAID:', shs(sale.amountPaid)),
          if (sale.hasLoan) ...[
            if (sale.customerName != null) kv('CUSTOMER:', sale.customerName!),
            kv('LOAN BALANCE:', shs(sale.loanAmount), bold: true),
            if (sale.loanPledgeDate != null)
              kv('PAYMENT DUE BY:', sale.loanPledgeDate!, bold: true),
            kv('STATUS:', 'ON CREDIT', bold: true),
          ] else ...[
            kv('CHANGE DUE:', shs(sale.changeDue), bold: true),
            kv('STATUS:', 'PAID (0 BAL)', bold: true),
          ],
          divider(),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: bc.Barcode.code128(),
              data: sale.id,
              width: w * 2.2,
              height: 26,
              drawText: false,
            ),
          ),
          pw.Center(
              child: pw.Text(sale.id,
                  style: const pw.TextStyle(
                      fontSize: 7, letterSpacing: 2, color: PdfColors.grey700))),
          pw.SizedBox(height: 6),
          pw.Center(
              child: pw.Text('THANK YOU FOR SHOPPING WITH US',
                  style: const pw.TextStyle(fontSize: 7))),
          pw.Center(
              child: pw.Text(AppBranding.receiptFooter,
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold))),
        ],
      ),
    ));
    return pdf.save();
  }

  static Future<void> printStickers(
    Product product, {
    required int count,
    required num price,
    required bool showBranding,
    required bool showExpiry,
    bool share = false,
  }) async {
    final pdf = pw.Document();
    pw.Widget sticker() => pw.Container(
          width: 50 * PdfPageFormat.mm,
          height: 30 * PdfPageFormat.mm,
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (showBranding)
                pw.Center(
                    child: pw.Text(AppBranding.receiptHeader,
                        style: pw.TextStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold))),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(product.name,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text('CAT: ${product.category}',
                    style: const pw.TextStyle(
                        fontSize: 5, color: PdfColors.grey600)),
              ]),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: bc.Barcode.code39(),
                  data: product.sku,
                  width: 130,
                  height: 26,
                  drawText: true,
                  textStyle: const pw.TextStyle(fontSize: 5),
                ),
              ),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (showExpiry && product.expirationDate != null)
                            pw.Text('EXP: ${product.expirationDate}',
                                style: const pw.TextStyle(fontSize: 5)),
                          pw.Text('LOC: MAIN STK',
                              style: const pw.TextStyle(fontSize: 5)),
                        ]),
                    pw.Text('shs ${money(price)}',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ]),
            ],
          ),
        );

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(count, (_) => sticker()),
      ),
    ));

    final bytes = await pdf.save();
    if (share) {
      await Printing.sharePdf(bytes: bytes, filename: 'stickers_${product.sku}.pdf');
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  static Future<void> printTest(PrinterSettings settings) async {
    final pdf = pw.Document();
    final w = _widthMm(settings);
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat(
          w * PdfPageFormat.mm, double.infinity,
          marginAll: 4 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Center(
              child: pw.Text('${AppBranding.labelBranding} POS TEST',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold))),
          pw.Center(
              child: pw.Text('Quality Commodities & High Speed',
                  style: const pw.TextStyle(fontSize: 7))),
          pw.SizedBox(height: 6),
          pw.Text('Paper Width:    ${settings.paperWidth}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Default Format: ${settings.defaultFormat}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text('IP Address:     ${settings.ipAddress}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Text('BT Address:     ${settings.bluetoothAddress}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 6),
          pw.Center(
              child: pw.Text('PRINTER CONNECTION OK',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Center(
              child: pw.Text(AppBranding.businessName,
                  style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }
}
