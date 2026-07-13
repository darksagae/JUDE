import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';

import 'package:apex_retail_core/branding.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/utils/print_service.dart';

/// Thermal-style receipt preview + print/share actions.
class ReceiptDialog extends StatelessWidget {
  final Sale sale;
  final PrinterSettings settings;
  const ReceiptDialog({super.key, required this.sale, required this.settings});

  static Future<void> show(
          BuildContext context, Sale sale, PrinterSettings settings) =>
      showDialog(
        context: context,
        builder: (_) => ReceiptDialog(sale: sale, settings: settings),
      );

  @override
  Widget build(BuildContext context) {
    final is80 = settings.paperWidth == '80mm';
    final screenW = MediaQuery.sizeOf(context).width;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
          horizontal: screenW < 400 ? 12 : 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: screenW < 400 ? screenW * 0.95 : (is80 ? 400 : 340),
            maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.slate50,
                border:
                    Border(bottom: BorderSide(color: AppColors.slate100)),
              ),
              child: Row(children: [
                const Icon(Icons.circle, size: 10, color: AppColors.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Receipt Issued (${settings.paperWidth})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate800)),
                ),
                IconButton(
                  tooltip: 'Share PDF',
                  icon: const Icon(Icons.download, size: 18),
                  onPressed: () => PrintService.shareReceipt(sale, settings),
                ),
                IconButton(
                  tooltip: 'Print',
                  icon: const Icon(Icons.print, size: 18),
                  onPressed: () => PrintService.printReceipt(sale, settings),
                ),
              ]),
            ),
            Expanded(
              child: Container(
                color: AppColors.slate100,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Center(child: _paper(is80)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.slate900),
                    onPressed: () => PrintService.printReceipt(sale, settings),
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Print'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald),
                    onPressed: () =>
                        PrintService.shareReceipt(sale, settings),
                    icon: const Icon(Icons.ios_share, size: 16),
                    label: const Text('Export'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dash() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: DottedLine(),
      );

  Widget _row(String a, String b, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(a,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: color,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text(b,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: color,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );

  Widget _paper(bool is80) {
    return Container(
      width: is80 ? 320 : 260,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.amber, width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
            fontFamily: 'monospace', fontSize: 11, color: AppColors.slate800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
                child: Text(AppBranding.receiptHeader,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13))),
            const Center(
                child: Text('Plot 12, Kampala Plaza Rd',
                    style: TextStyle(fontSize: 9, color: AppColors.slate500))),
            const Center(
                child: Text('Tel: +256 702 345 678',
                    style: TextStyle(fontSize: 9, color: AppColors.slate500))),
            _dash(),
            Text('SALE ID: ${sale.id}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            Text('Date/Time: ${fmtDateTime(sale.timestamp)}',
                style: const TextStyle(fontSize: 10, color: AppColors.slate500)),
            Text('Cashier: ${sale.cashierName} (${sale.cashierId})',
                style: const TextStyle(fontSize: 10, color: AppColors.slate500)),
            _dash(),
            Row(children: const [
              Expanded(
                  flex: 3,
                  child: Text('ITEM',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text('QTY',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('TOTAL',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold))),
            ]),
            _dash(),
            ...sale.items.map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            flex: 3,
                            child: Text(it.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10))),
                        Expanded(
                            child: Text('x${it.quantity}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 10))),
                        Expanded(
                            flex: 2,
                            child: Text(money(it.totalSellingPrice),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 10))),
                      ]),
                      Text(
                          '@ ${money(it.sellingPrice)} / unit'
                          '${it.isWholesale ? ' (WHOLESALE)' : ''}',
                          style: const TextStyle(
                              fontSize: 8, color: AppColors.slate400)),
                    ],
                  ),
                )),
            _dash(),
            _row('SUBTOTAL:', shs(sale.totalAmount)),
            _row('TOTAL:', shs(sale.totalAmount), bold: true),
            _dash(),
            _row('PAY METHOD:',
                sale.paymentMethod.replaceAll('_', ' ').toUpperCase(),
                color: AppColors.slate500),
            if (sale.paymentMethod == 'mobile_money' &&
                sale.mobileMoneyTxId != null)
              _row('REF TXID:', sale.mobileMoneyTxId!,
                  bold: true, color: AppColors.indigo700),
            _row('CASH PAID:', shs(sale.amountPaid), color: AppColors.slate500),
            if (sale.hasLoan) ...[
              if (sale.customerName != null)
                _row('CUSTOMER:', sale.customerName!,
                    color: AppColors.slate500),
              _row('LOAN BALANCE:', shs(sale.loanAmount),
                  bold: true, color: AppColors.rose),
              if (sale.loanPledgeDate != null)
                _row('PAYMENT DUE BY:', sale.loanPledgeDate!,
                    bold: true, color: AppColors.rose),
              _row('STATUS:', 'ON CREDIT', bold: true, color: AppColors.rose),
            ] else ...[
              _row('CHANGE DUE:', shs(sale.changeDue),
                  bold: true, color: AppColors.emerald),
              _row('STATUS:', 'PAID (0 BAL)',
                  bold: true, color: AppColors.emerald),
            ],
            _dash(),
            const SizedBox(height: 4),
            Center(
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: sale.id,
                width: is80 ? 220 : 176,
                height: 40,
                drawText: false,
                color: AppColors.slate900,
              ),
            ),
            const SizedBox(height: 4),
            Center(
                child: Text(sale.id,
                    style: const TextStyle(
                        fontSize: 9,
                        letterSpacing: 3,
                        color: AppColors.slate400))),
            const SizedBox(height: 10),
            const Center(
                child: Text('THANK YOU FOR SHOPPING WITH US',
                    style: TextStyle(fontSize: 9, color: AppColors.slate400))),
            const Center(
                child: Text(AppBranding.receiptFooter,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate600))),
          ],
        ),
      ),
    );
  }
}

class DottedLine extends StatelessWidget {
  const DottedLine({super.key});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final count = (c.maxWidth / 5).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
            count,
            (_) => const SizedBox(
                width: 2,
                height: 1,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.slate400)))),
      );
    });
  }
}
