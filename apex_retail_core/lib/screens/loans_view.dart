import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/utils/input_formatters.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/utils/responsive.dart';

class LoansView extends StatefulWidget {
  // Loans are only ever registered from the POS checkout flow — the Admin
  // console is read-only for creation (it can still record payments).
  final bool canRegister;
  const LoansView({super.key, this.canRegister = true});
  @override
  State<LoansView> createState() => _LoansViewState();
}

class _LoansViewState extends State<LoansView> {
  final _search = TextEditingController();
  String _filter = 'active'; // active | overdue | settled | all
  bool _refreshing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // `neutral` is for expected offline/no-connection states — this app is
  // designed to keep working without internet, so that isn't an error and
  // shouldn't be flagged red like one.
  void _msg(String text, {bool err = false, bool neutral = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor:
          err ? AppColors.rose : (neutral ? AppColors.amber600 : AppColors.emerald),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    setState(() => _refreshing = true);
    try {
      if (app.offlineMode) {
        _msg('Offline Mode: showing local loan records.', neutral: true);
      } else {
        await app.triggerSync();
        _msg('Loan ledger synced with the cloud.');
      }
    } catch (_) {
      _msg('No connection — showing local loan records.', neutral: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final term = _search.text.toLowerCase();
    var loans = app.loans.where((l) {
      final matchS = l.customerName.toLowerCase().contains(term) ||
          l.customerContact.toLowerCase().contains(term) ||
          (l.saleId ?? '').toLowerCase().contains(term);
      final matchF = switch (_filter) {
        'active' => !l.isSettled,
        'overdue' => l.isOverdue(),
        'settled' => l.isSettled,
        _ => true,
      };
      return matchS && matchF;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveHeader(
          title: 'LOANS & CREDIT LEDGER',
          action: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 14),
              label: const Text('Pull Cloud Updates'),
            ),
            if (widget.canRegister)
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.indigo),
                onPressed: () => _openLoanForm(app),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Register Loan'),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        _summaryRow(app),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(builder: (context, c) {
                final narrow = c.maxWidth < 560;
                final search = TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search by customer, contact, or sale...',
                  ),
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 10),
                      _filterChips(),
                    ],
                  );
                }
                return Row(children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  _filterChips(),
                ]);
              }),
              const SizedBox(height: 12),
              if (loans.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('No loans match this view.',
                          style: TextStyle(color: AppColors.slate400))),
                )
              else
                ...loans.map((l) => _loanTile(app, l)),
            ],
          ),
        ),
      ],
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

  Widget _summaryRow(AppState app) {
    Widget stat(String label, String value, Color color, IconData icon) =>
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate100)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.slate400)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                ],
              ),
            ),
          ]),
        );

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 640;
      final cards = [
        stat('Outstanding', shs(app.totalOutstandingLoans), AppColors.indigo,
            Icons.account_balance_wallet_outlined),
        stat('Overdue', '${app.overdueLoans.length}', AppColors.rose,
            Icons.error_outline),
        stat('Due Soon', '${app.dueSoonLoans.length}', AppColors.amber600,
            Icons.schedule),
      ];
      if (narrow) {
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              cards[i],
            ],
          ],
        );
      }
      return Row(children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
      ]);
    });
  }

  Widget _filterChips() {
    return Wrap(spacing: 6, children: [
      for (final f in ['active', 'overdue', 'settled', 'all'])
        GestureDetector(
          onTap: () => setState(() => _filter = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _filter == f ? AppColors.slate900 : Colors.white,
              border: Border.all(color: AppColors.slate200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(f[0].toUpperCase() + f.substring(1),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _filter == f ? Colors.white : AppColors.slate600)),
          ),
        ),
    ]);
  }

  Widget _loanTile(AppState app, Loan l) {
    final overdue = l.isOverdue();
    final settled = l.isSettled;
    final statusColor = settled
        ? AppColors.emerald
        : overdue
            ? AppColors.rose
            : (l.daysUntilDue() <= 3 ? AppColors.amber600 : AppColors.indigo);
    final statusText = settled
        ? 'PAID'
        : overdue
            ? 'OVERDUE'
            : 'Due in ${l.daysUntilDue()}d';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: settled ? AppColors.slate50 : Colors.white,
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
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
                    child: Text(l.customerName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(statusText,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                    '${l.customerContact.isEmpty ? 'No contact' : l.customerContact} • pledged ${l.pledgeDate}'
                    '${l.saleId != null ? ' • ${l.saleId}' : ''}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.slate400)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(shs(l.balance),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: statusColor)),
              Text('of ${shs(l.originalAmount)}',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.slate400)),
            ],
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 6,
          children: [
          if (l.createdByName.isNotEmpty)
            Text('Registered by ${l.createdByName}',
                style:
                    const TextStyle(fontSize: 10, color: AppColors.slate400)),
          if (!settled)
            OutlinedButton.icon(
              onPressed: () => _recordPayment(app, l),
              icon: const Icon(Icons.payments_outlined, size: 14),
              label: const Text('Record Payment'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  foregroundColor: AppColors.emerald),
            ),
          if (widget.canRegister)
            OutlinedButton.icon(
              onPressed: () => _addToLoan(app, l),
              icon: const Icon(Icons.add_circle_outline, size: 14),
              label: const Text('Add to Loan'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  foregroundColor: AppColors.amber600),
            ),
          if (app.session.role == UserRole.topManager)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.slate400),
              onPressed: () => app.deleteLoan(l.id),
            ),
        ]),
      ]),
    );
  }

  void _openLoanForm(AppState app) {
    final name = TextEditingController();
    final contact = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    final pledge = TextEditingController(
        text: DateTime.now()
            .add(const Duration(days: 7))
            .toIso8601String()
            .substring(0, 10));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        return AlertDialog(
          title: const Text('Register a Loan'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 400)),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _f('Customer full name *', name),
                _f('Contact (phone) ', contact),
                _f('Loan amount (shs) *', amount, num: true),
                _dateField('Pledged repayment date *', pledge, ctx, setModal),
                _f('Notes', notes),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amt = num.tryParse(amount.text);
                if (name.text.trim().isEmpty || amt == null || amt <= 0) return;
                app.addLoan(
                  customerName: name.text.trim(),
                  customerContact: contact.text.trim(),
                  amount: amt,
                  pledgeDate: pledge.text.trim(),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Register Loan'),
            ),
          ],
        );
      }),
    );
  }

  void _recordPayment(AppState app, Loan l) {
    final amount = TextEditingController(text: l.balance.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment — ${l.customerName}',
            style: const TextStyle(fontSize: 16)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: Responsive.dialogWidth(ctx, max: 320)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Outstanding balance: ${shs(l.balance)}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
            const SizedBox(height: 8),
            _f('Amount received (shs) *', amount, num: true),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () {
              final amt = num.tryParse(amount.text);
              if (amt == null || amt <= 0) return;
              app.recordLoanPayment(l.id, amt);
              Navigator.pop(ctx);
            },
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
  }

  void _addToLoan(AppState app, Loan l) {
    final amount = TextEditingController();
    final notes = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add to Loan — ${l.customerName}',
            style: const TextStyle(fontSize: 16)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: Responsive.dialogWidth(ctx, max: 320)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Current balance: ${shs(l.balance)}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
            const SizedBox(height: 8),
            _f('Additional amount (shs) *', amount, num: true),
            _f('Notes', notes),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.amber600),
            onPressed: () {
              final amt = num.tryParse(amount.text);
              if (amt == null || amt <= 0) return;
              app.increaseLoan(l.id, amt,
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Add to Loan'),
          ),
        ],
      ),
    );
  }

  Widget _f(String label, TextEditingController c, {bool num = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          keyboardType: num ? TextInputType.number : TextInputType.text,
          inputFormatters: num ? const [NoLeadingZeroFormatter()] : null,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _dateField(String label, TextEditingController c, BuildContext ctx,
      void Function(void Function()) setModal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        onTap: () async {
          final init = DateTime.tryParse(c.text) ?? DateTime.now();
          final picked = await showDatePicker(
            context: ctx,
            initialDate: init,
            firstDate: DateTime.now().subtract(const Duration(days: 30)),
            lastDate: DateTime(2032),
          );
          if (picked != null) {
            setModal(() => c.text = picked.toIso8601String().substring(0, 10));
          }
        },
      ),
    );
  }
}
