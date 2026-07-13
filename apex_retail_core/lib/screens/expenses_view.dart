import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/utils/input_formatters.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/utils/responsive.dart';

const _expenseCategories = [
  'Restock / Purchases',
  'Rent',
  'Utilities (Power/Water)',
  'Salaries / Wages',
  'Transport',
  'Maintenance',
  'Licenses / Taxes',
  'Marketing',
  'Miscellaneous',
];

class ExpensesView extends StatefulWidget {
  const ExpensesView({super.key});
  @override
  State<ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends State<ExpensesView> {
  String _period = 'all';

  List<Expense> _filtered(List<Expense> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return all.where((e) {
      final dt = DateTime.tryParse(e.timestamp)?.toLocal();
      if (dt == null) return false;
      final day = DateTime(dt.year, dt.month, dt.day);
      switch (_period) {
        case 'today':
          return day == today;
        case 'weekly':
          return today.difference(day).inDays <= 7;
        case 'monthly':
          return today.difference(day).inDays <= 30;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = _filtered(app.expenses);
    final total = list.fold<num>(0, (a, e) => a + e.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveHeader(
          title: 'BUSINESS EXPENDITURES',
          action: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.slate900),
            onPressed: () => _openForm(app),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Record Cost'),
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 520;
            final totalCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Expenditure (period)',
                    style: TextStyle(fontSize: 12, color: AppColors.slate400)),
                Text(shs(total),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.rose)),
              ],
            );
            final chips = Wrap(spacing: 6, children: [
              for (final p in ['today', 'weekly', 'monthly', 'all'])
                GestureDetector(
                  onTap: () => setState(() => _period = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _period == p
                          ? AppColors.slate900
                          : AppColors.slate50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(p == 'all' ? 'All' : p,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _period == p
                                ? Colors.white
                                : AppColors.slate500)),
                  ),
                ),
            ]);
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  totalCol,
                  const SizedBox(height: 12),
                  chips,
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [totalCol, chips],
            );
          }),
        ),
        const SizedBox(height: 16),
        _card(
          child: list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: Text('No expenditures recorded for this period.',
                          style: TextStyle(color: AppColors.slate400))),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 24,
                    headingRowHeight: 40,
                    columns: const [
                      DataColumn(label: Text('Date & Time')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Amount'), numeric: true),
                      DataColumn(label: Text('Recorded By')),
                      DataColumn(label: Text('')),
                    ],
                    rows: list
                        .map((e) => DataRow(cells: [
                              DataCell(Text(fmtDateTime(e.timestamp),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.slate400))),
                              DataCell(Text(e.category,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(e.description)),
                              DataCell(Text(shs(e.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.rose))),
                              DataCell(Text(e.recordedByName,
                                  style: const TextStyle(fontSize: 11))),
                              DataCell(app.session.role == UserRole.topManager
                                  ? IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 16, color: AppColors.slate400),
                                      onPressed: () => app.deleteExpense(e.id),
                                    )
                                  : const SizedBox.shrink()),
                            ]))
                        .toList(),
                  ),
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

  void _openForm(AppState app) {
    var category = _expenseCategories.first;
    final desc = TextEditingController();
    final amount = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Business Cost'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: Responsive.dialogWidth(ctx, max: 380)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category *'),
              items: _expenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => category = v ?? category,
            ),
            const SizedBox(height: 10),
            TextField(
                controller: desc,
                decoration:
                    const InputDecoration(labelText: 'Description *')),
            const SizedBox(height: 10),
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: const [NoLeadingZeroFormatter()],
                decoration: const InputDecoration(labelText: 'Amount (shs) *')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final amt = num.tryParse(amount.text);
              if (desc.text.trim().isEmpty || amt == null || amt <= 0) return;
              app.addExpense(
                  category: category,
                  description: desc.text.trim(),
                  amount: amt);
              Navigator.pop(ctx);
            },
            child: const Text('Save Cost'),
          ),
        ],
      ),
    );
  }
}
