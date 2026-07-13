import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/utils/responsive.dart';
import 'package:apex_retail_core/widgets/receipt_dialog.dart';

class SalesLedgerView extends StatefulWidget {
  const SalesLedgerView({super.key});
  @override
  State<SalesLedgerView> createState() => _SalesLedgerViewState();
}

class _SalesLedgerViewState extends State<SalesLedgerView> {
  final _search = TextEditingController();
  Sale? _selected;
  bool _refreshing = false;
  String? _deletingId;
  String _period = 'today';
  DateTime? _customDate;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _msg(String text, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: err ? AppColors.rose : AppColors.emerald,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    setState(() => _refreshing = true);
    try {
      if (app.offlineMode) {
        _msg('Offline Mode: Reading offline sales history only.', err: true);
      } else {
        await app.triggerSync();
        _msg('Successfully pulled transaction ledger updates!');
      }
    } catch (_) {
      _msg('Cloud pull deferred. Offline ledger fallback loaded.', err: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _void(Sale sale) async {
    final app = context.read<AppState>();
    final isOwn = sale.cashierId == app.session.userId;
    // Staff (workers) may delete their own transactions; managers and the top
    // manager may void any. The audit ledger surfaces every deletion up the
    // hierarchy so supervisors can see what was removed and by whom.
    if (!app.session.role.isManagerial && !isOwn) {
      _msg('You can only void your own transactions.', err: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void Transaction'),
        content: Text(
            'Void transaction ${sale.id}? This deletes the sale record and replenishes stock levels.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Void Sale')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deletingId = sale.id);
    try {
      if (app.offlineMode) {
        app.voidSaleLocal(sale.id);
        _msg('Transaction voided locally (Offline).');
      } else {
        await app.voidSaleRemote(sale.id);
        _msg('Transaction ${sale.id} voided. Stock restored!');
      }
      setState(() => _selected = null);
    } catch (e) {
      _msg('Failed to void transaction: $e', err: true);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final term = _search.text.toLowerCase();
    final sales = app.sales.where((s) {
      if (!saleMatchesPeriod(s.timestamp, _period, _customDate)) return false;
      return s.id.toLowerCase().contains(term) ||
          s.cashierName.toLowerCase().contains(term) ||
          s.cashierId.toLowerCase().contains(term) ||
          s.items.any((it) => it.productName.toLowerCase().contains(term));
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final periodTotal =
        sales.fold<num>(0, (sum, s) => sum + s.totalAmount);
    final periodProfit =
        sales.fold<num>(0, (sum, s) => sum + s.totalProfit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveHeader(
          title: 'TRANSACTION & SALES LEDGER',
          action: OutlinedButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 14),
            label: const Text('Pull Cloud Updates'),
          ),
        ),
        const SizedBox(height: 16),
        _buildPeriodFilters(),
        _periodSummary(sales.length, periodTotal, periodProfit),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 860;
          final list = _list(sales, app);
          final detail = _detail(app);
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: list),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: detail),
              ],
            );
          }
          return Column(children: [list, const SizedBox(height: 20), detail]);
        }),
      ],
    );
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _customDate = picked;
        _period = 'custom';
        _selected = null;
      });
    }
  }

  Widget _periodChip(String id, String label) {
    final active = _period == id;
    return GestureDetector(
      onTap: () => setState(() {
        _period = id;
        _selected = null;
        if (id != 'custom') _customDate = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.slate900 : Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.slate600)),
      ),
    );
  }

  Widget _buildPeriodFilters() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _periodChip('today', 'Today'),
          const SizedBox(width: 6),
          _periodChip('yesterday', 'Yesterday'),
          const SizedBox(width: 6),
          _periodChip('week', 'Weekly'),
          const SizedBox(width: 6),
          _periodChip('month', 'Month'),
          const SizedBox(width: 6),
          _periodChip('all', 'All time'),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _pickCustomDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color:
                    _period == 'custom' ? AppColors.amber600 : Colors.white,
                border: Border.all(color: AppColors.slate200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today_outlined,
                    size: 12,
                    color: _period == 'custom'
                        ? Colors.white
                        : AppColors.slate600),
                const SizedBox(width: 4),
                Text(
                  _period == 'custom'
                      ? salesPeriodLabel('custom', _customDate)
                      : 'Custom date',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _period == 'custom'
                          ? Colors.white
                          : AppColors.slate600),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodSummary(int count, num total, num profit) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 420;
        final label =
            '${salesPeriodLabel(_period, _customDate)} • $count sales';
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate700)),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, children: [
                Text('Revenue ${shs(total)}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
                Text('Profit ${shs(profit)}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.emerald)),
              ]),
            ],
          );
        }
        return Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate700)),
          ),
          Text('Revenue ${shs(total)}',
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Text('Profit ${shs(profit)}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.emerald)),
        ]);
      }),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slate100),
        ),
        child: child,
      );

  Widget _list(List<Sale> sales, AppState app) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search by Transaction ID, item, or cashier...',
            ),
          ),
          const SizedBox(height: 12),
          if (sales.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                  child: Text(
                      'No transactions for ${salesPeriodLabel(_period, _customDate).toLowerCase()}.',
                      style: const TextStyle(color: AppColors.slate400))),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sales.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _saleTile(sales[i], app),
              ),
            ),
        ],
      ),
    );
  }

  Widget _saleTile(Sale sale, AppState app) {
    final selected = _selected?.id == sale.id;
    return InkWell(
      onTap: () => setState(() => _selected = sale),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          border: Border.all(
              color: selected ? AppColors.indigo : AppColors.slate100),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(sale.id,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    if (!sale.synced) ...[
                      const SizedBox(width: 6),
                      _tag('Offline Cache'),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                      '${fmtTime(sale.timestamp)} • ${fmtShortDate(sale.timestamp)}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.slate400)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(shs(sale.totalAmount),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14)),
                Text(paymentLabel(sale.paymentMethod).toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.slate400)),
                if (app.session.role.isManagerial)
                  Text('Profit: ${shs(sale.totalProfit)}',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.emerald)),
              ],
            ),
          ]),
          const Divider(height: 16, color: AppColors.slate100),
          Row(children: [
            const Icon(Icons.person_outline, size: 12, color: AppColors.slate400),
            const SizedBox(width: 4),
            Expanded(
              child: Text('Cashier: ${sale.cashierName} (${sale.cashierId})',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.slate500)),
            ),
            Text('${sale.items.fold<int>(0, (a, i) => a + i.quantity.toInt())} items',
                style:
                    const TextStyle(fontSize: 10, color: AppColors.slate400)),
          ]),
        ]),
      ),
    );
  }

  Widget _tag(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(4)),
        child: Text(s,
            style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: AppColors.amber600)),
      );

  Widget _detail(AppState app) {
    final sale = _selected;
    if (sale == null) {
      return _card(
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(
            child: Column(children: [
              Icon(Icons.receipt_long, size: 28, color: AppColors.slate400),
              SizedBox(height: 12),
              Text('Select a transaction to view details, void, or print.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.slate400, fontSize: 12)),
            ]),
          ),
        ),
      );
    }
    final canVoid = app.session.role.isManagerial ||
        sale.cashierId == app.session.userId;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 400;
            final voidBtn = canVoid
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE2E2),
                        foregroundColor: AppColors.red),
                    onPressed:
                        _deletingId == sale.id ? null : () => _void(sale),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: Text(
                        _deletingId == sale.id ? 'Voiding...' : 'Void Sale'),
                  )
                : const Text('Not your transaction',
                    style: TextStyle(fontSize: 10, color: AppColors.slate500));
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TRANSACTION DETAIL',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.slate800)),
                      Text(sale.id,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.indigo)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  voidBtn,
                ],
              );
            }
            return Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TRANSACTION DETAIL',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slate800)),
                    Text(sale.id,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.indigo)),
                  ],
                ),
              ),
              voidBtn,
            ]);
          }),
          const Divider(height: 24, color: AppColors.slate100),
          const Text('RECEIPT SNAPSHOT',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate400)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: sale.items
                  .map((it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                                child: Text(
                                    '${it.productName} x${it.quantity}'
                                    '${it.isWholesale ? ' (Wholesale)' : ''}',
                                    style: const TextStyle(fontSize: 12))),
                            Text(shs(it.sellingPrice * it.quantity),
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(runSpacing: 10, children: [
            _kv('Payment', paymentLabel(sale.paymentMethod)),
            _kv('Cashier', '${sale.cashierName} (${sale.cashierId})'),
            _kv('Amount Tendered', shs(sale.amountPaid)),
            _kv('Change Given', shs(sale.changeDue)),
            if (app.session.role.isManagerial)
              _kv('Profit', shs(sale.totalProfit)),
            if (sale.paymentMethod == 'mobile_money' &&
                sale.mobileMoneyTxId != null)
              _kv('TxID', sale.mobileMoneyTxId!),
            if (sale.hasLoan) ...[
              _kv('Loan Customer', sale.customerName ?? 'Walk-in Customer'),
              _kv('Loan Balance', shs(sale.loanAmount)),
              if (sale.loanPledgeDate != null)
                _kv('Payment Due By', sale.loanPledgeDate!),
            ],
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () =>
                ReceiptDialog.show(context, sale, app.printerSettings),
            icon: const Icon(Icons.print, size: 16),
            label: const Text('View / Print Receipt'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.slate400)),
            Text(v,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
