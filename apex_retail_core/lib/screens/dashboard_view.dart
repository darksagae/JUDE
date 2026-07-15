import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/data/id.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/utils/responsive.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});
  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  String _period = 'all';
  bool _balancing = false;
  bool _refreshing = false;
  EndOfDayReport? _activeReport;
  final _ownerContact = TextEditingController(text: '+256 702 345 678');

  @override
  void dispose() {
    _ownerContact.dispose();
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
        _msg('Offline Mode: showing local sales data.', neutral: true);
      } else {
        await app.triggerSync();
        _msg('Dashboard synced with the cloud.');
      }
    } catch (_) {
      _msg('No connection — showing local sales data.', neutral: true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Whether a local timestamp falls inside the currently-selected period.
  /// Shared by sales and loan-repayment aggregation so both use one definition.
  bool _inPeriod(DateTime local) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(local.year, local.month, local.day);
    switch (_period) {
      case 'today':
        return day == today;
      case 'yesterday':
        return day == yesterday;
      case 'weekly':
        final d = today.difference(day).inDays;
        return d >= 0 && d <= 7;
      case 'monthly':
        final d = today.difference(day).inDays;
        return d >= 0 && d <= 30;
      case 'yearly':
        return local.year == now.year;
      default:
        return true;
    }
  }

  List<Sale> _filtered(List<Sale> sales) {
    return sales.where((s) {
      final dt = DateTime.tryParse(s.timestamp);
      if (dt == null) return false;
      return _inPeriod(dt.toLocal());
    }).toList();
  }

  Future<void> _runEod() async {
    final app = context.read<AppState>();
    setState(() {
      _balancing = true;
      _activeReport = null;
    });
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final todaySales = app.sales.where((s) {
      final dt = DateTime.tryParse(s.timestamp)?.toLocal();
      if (dt == null) return false;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();
    try {
      final report = await app.analyzeEod(todaySales, todayStr);
      // Cash-basis EOD balance — cash collected today = cash paid on today's
      // sales PLUS loan repayments received today. Profit is recognized on the
      // cash portion of sales plus the profit realized from today's repayments.
      bool sameDayAsNow(DateTime d) =>
          d.year == now.year && d.month == now.month && d.day == now.day;
      final coll = app.loanCollections(sameDayAsNow);
      final totalSales =
          todaySales.fold<num>(0, (a, s) => a + s.amountPaid) + coll.cash;
      final totalProfit =
          todaySales.fold<num>(0, (a, s) => a + app.recognizedSaleProfit(s)) +
              coll.profit;
      final totalStaked =
          todaySales.fold<num>(0, (a, s) => a + s.totalBuyingPrice);
      final newReport = EndOfDayReport(
        id: 'EOD-${todayStr.replaceAll('-', '')}-${randInt(100, 999)}',
        date: todayStr,
        totalSales: totalSales,
        totalProfit: totalProfit,
        totalStaked: totalStaked,
        salesCount: todaySales.length,
        reportDrawnBy: app.session.name,
        reportDrawnAt: DateTime.now().toUtc().toIso8601String(),
        ownerNotificationSent: false,
        ownerContact: _ownerContact.text,
        aiInsights: jsonEncode(report),
      );
      app.setReports([newReport, ...app.reports]);
      app.logAction(app.session.userId, app.session.name, app.session.role,
          'EOD_BALANCE',
          'Generated automated EOD Balance Report for $todayStr. Total Sales: ${shs(totalSales)}');
      setState(() => _activeReport = newReport);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error generating EOD balancing analysis')));
      }
    } finally {
      if (mounted) setState(() => _balancing = false);
    }
  }

  void _sendNotification(Map<String, dynamic>? insights) {
    final app = context.read<AppState>();
    showDialog(
      context: context,
      builder: (ctx) {
        final draft = insights?['ownerMessageDraft'] as String? ??
            '🌾 DAILY BUSINESS REPORT - ${_activeReport!.date}\nTotal Sales: ${shs(_activeReport!.totalSales)}\nNet Profit: ${shs(_activeReport!.totalProfit)}';
        return AlertDialog(
          title: const Text('Send Dispatch Ledger'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 380)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ownerContact,
                  decoration:
                      const InputDecoration(labelText: 'Owner Contact Number'),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(draft,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final updated = app.reports.map((r) {
                  if (r.id == _activeReport!.id) r.ownerNotificationSent = true;
                  return r;
                }).toList();
                app.setReports(updated);
                app.logAction(app.session.userId, app.session.name,
                    app.session.role, 'EOD_BALANCE',
                    'SMS daily ledger successfully dispatched to owner at ${_ownerContact.text}');
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Summary dispatched to owner.')));
              },
              child: const Text('Confirm & Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final filtered = _filtered(app.sales);
    // Cash-basis: only money actually collected counts. That's the cash paid at
    // checkout PLUS loan repayments received in this period. Profit is likewise
    // recognized on the cash portion of each sale, with the credit portion's
    // profit realized as those loans are repaid.
    final coll = app.loanCollections(_inPeriod);
    final revenue =
        filtered.fold<num>(0, (a, s) => a + s.amountPaid) + coll.cash;
    final staked = filtered.fold<num>(0, (a, s) => a + s.totalBuyingPrice);
    final profit =
        filtered.fold<num>(0, (a, s) => a + app.recognizedSaleProfit(s)) +
            coll.profit;

    final outOfStock =
        app.products.where((p) => p.currentStock <= 0).toList();
    final lowStock = app.products
        .where((p) => p.currentStock > 0 && p.currentStock <= p.minStockLevel)
        .toList();
    final expiring = app.products.where((p) => isProductNearExpiry(p)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _periodBar(),
        const SizedBox(height: 16),
        _metricsRow(revenue, staked, profit, filtered.length),
        const SizedBox(height: 16),
        if (outOfStock.isNotEmpty || lowStock.isNotEmpty || expiring.isNotEmpty) ...[
          _alertsRow(outOfStock, lowStock, expiring),
          const SizedBox(height: 16),
        ],
        _chartsRow(app, filtered),
        const SizedBox(height: 16),
        _leaderboard(app, filtered),
        const SizedBox(height: 16),
        _workerLeaderboard(filtered),
        if (_activeReport != null) ...[
          const SizedBox(height: 16),
          _reportPanel(),
        ],
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slate100),
        ),
        child: child,
      );

  Widget _periodBar() {
    const periods = ['today', 'yesterday', 'weekly', 'monthly', 'yearly', 'all'];
    return _card(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        children: [
          Wrap(
            spacing: 6,
            children: periods.map((p) {
              final active = _period == p;
              return GestureDetector(
                onTap: () => setState(() => _period = p),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? AppColors.slate900 : AppColors.slate50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(p == 'all' ? 'All-Time' : p,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : AppColors.slate500)),
                ),
              );
            }).toList(),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
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
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.slate900),
              onPressed: _balancing ? null : _runEod,
              icon: _balancing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome,
                      size: 14, color: AppColors.amber),
              label: Text(_balancing ? 'Balancing...' : 'Automatic EOD Balance'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _metricsRow(num revenue, num staked, num profit, int count) {
    final items = [
      _MetricData('Cash Revenue (excl. Loans)', shs(revenue), Icons.trending_up,
          const Color(0xFFEEF2FF), AppColors.indigo),
      _MetricData('Staked Capital (Cost)', shs(staked), Icons.savings_outlined,
          const Color(0xFFFFFBEB), AppColors.amber600),
      _MetricData('Net Profit / Loss', shs(profit), Icons.attach_money,
          const Color(0xFFECFDF5), profit >= 0 ? AppColors.emerald : AppColors.red),
      _MetricData('Total Transactions', '$count', Icons.inventory_2_outlined,
          const Color(0xFFF5F3FF), const Color(0xFF7C3AED)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 500 ? 2 : 1);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        children: items.map(_metricCard).toList(),
      );
    });
  }

  Widget _metricCard(_MetricData m) => _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(m.label,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.slate400)),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(m.value,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: m.iconColor)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: m.bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(m.icon, size: 20, color: m.iconColor),
            ),
          ],
        ),
      );

  Widget _alertsRow(List<Product> outOfStock, List<Product> lowStock,
      List<Product> expiring) {
    Widget panel(String title, List<Product> items, Color color, Color bg,
        String Function(Product) trailing) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: color.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('$title (${items.length})',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ]),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Column(
                    children: items
                        .map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12))),
                                  Text(trailing(p),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: color)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        );
    }

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 900;
      final outPanel = panel(
          'Out of Stock', outOfStock, AppColors.red, const Color(0xFFFEF2F2),
          (p) => '0 left');
      final lowPanel = panel(
          'Low Inventory Alerts',
          lowStock,
          AppColors.amber600,
          const Color(0xFFFFFBEB),
          (p) => '${p.currentStock} left (Min: ${p.minStockLevel})');
      final expPanel = panel(
          'Critical Expiration',
          expiring,
          AppColors.red,
          const Color(0xFFFEF2F2),
          (p) => 'Exp: ${p.expirationDate}');
      final panels = [
        if (outOfStock.isNotEmpty) outPanel,
        if (lowStock.isNotEmpty) lowPanel,
        if (expiring.isNotEmpty) expPanel,
      ];
      if (narrow) {
        return Column(
          children: [
            for (var i = 0; i < panels.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              panels[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < panels.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: panels[i]),
          ],
        ],
      );
    });
  }

  Widget _chartsRow(AppState app, List<Sale> filtered) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 800;
      final trend = _trendChart(app.sales);
      final pie = _pieChart(app, filtered);
      if (wide) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 8, child: trend),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: pie),
            ],
          ),
        );
      }
      return Column(children: [trend, const SizedBox(height: 16), pie]);
    });
  }

  Widget _trendChart(List<Sale> sales) {
    final app = context.read<AppState>();
    final sorted = [...sales]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final groups = <String, List<num>>{};
    for (final s in sorted) {
      final dt = DateTime.tryParse(s.timestamp)?.toUtc();
      if (dt == null) continue;
      final label =
          '${s.timestamp.split('T')[0]} ${dt.hour}:00';
      groups.putIfAbsent(label, () => [0, 0]);
      groups[label]![0] += s.amountPaid;
      groups[label]![1] += app.recognizedSaleProfit(s);
    }
    final entries = groups.entries.toList();
    final tail = entries.length > 10
        ? entries.sublist(entries.length - 10)
        : entries;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Financial Velocity Trend',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.slate800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: tail.isEmpty
                ? const Center(
                    child: Text('No Sales registered in selected periods',
                        style: TextStyle(color: AppColors.slate400)))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (v) => const FlLine(
                              color: AppColors.slate100, strokeWidth: 1)),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 42,
                                getTitlesWidget: (v, _) => Text(
                                    _compact(v),
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: AppColors.slate400)))),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        _line(tail.map((e) => e.value[0]).toList(),
                            AppColors.indigo),
                        _line(tail.map((e) => e.value[1]).toList(),
                            AppColors.emerald),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            _Legend(color: AppColors.indigo, label: 'Revenue'),
            SizedBox(width: 16),
            _Legend(color: AppColors.emerald, label: 'Profit'),
          ]),
        ],
      ),
    );
  }

  LineChartBarData _line(List<num> values, Color color) => LineChartBarData(
        spots: [
          for (var i = 0; i < values.length; i++)
            FlSpot(i.toDouble(), values[i].toDouble())
        ],
        isCurved: true,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
            show: true, color: color.withValues(alpha: 0.12)),
      );

  String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  Widget _pieChart(AppState app, List<Sale> filtered) {
    final cats = <String, num>{};
    for (final s in filtered) {
      for (final it in s.items) {
        final prod = app.products
            .where((p) => p.id == it.productId)
            .cast<Product?>()
            .firstOrNull;
        final cat = prod?.category ?? 'General';
        cats[cat] = (cats[cat] ?? 0) + it.totalSellingPrice;
      }
    }
    final entries = cats.entries.toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sales by Commodity Category',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.slate800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: entries.isEmpty
                ? const Center(
                    child: Text('No categorical sales logged',
                        style: TextStyle(color: AppColors.slate400)))
                : PieChart(
                    PieChartData(
                      centerSpaceRadius: 45,
                      sectionsSpace: 3,
                      sections: [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value.toDouble(),
                            color:
                                AppColors.chart[i % AppColors.chart.length],
                            radius: 26,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          ...List.generate(entries.length, (i) {
            final e = entries[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: AppColors.chart[i % AppColors.chart.length],
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                Text(shs(e.value),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _leaderboard(AppState app, List<Sale> filtered) {
    final counts = <String, Map<String, dynamic>>{};
    for (final s in filtered) {
      // Cash-basis: only count the profit on the paid fraction of this sale.
      final paidFrac = s.totalAmount > 0 ? s.amountPaid / s.totalAmount : 1;
      for (final it in s.items) {
        final prod = app.products
            .where((p) => p.id == it.productId)
            .cast<Product?>()
            .firstOrNull;
        counts.putIfAbsent(
            it.productId,
            () => {
                  'name': it.productName,
                  'quantity': 0 as num,
                  'revenue': 0 as num,
                  'profit': 0 as num,
                  'category': prod?.category ?? 'General',
                  'sku': prod?.sku ?? '',
                });
        counts[it.productId]!['quantity'] += it.quantity;
        counts[it.productId]!['revenue'] += it.totalSellingPrice;
        counts[it.productId]!['profit'] += it.profit * paidFrac;
      }
    }
    final list = counts.values.toList()
      ..sort((a, b) => (b['quantity'] as num).compareTo(a['quantity'] as num));
    final top = list.take(10).toList();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🛒 Commodity Popularity & Sales Leaderboard',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.slate800)),
          const SizedBox(height: 12),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                  child: Text('No sales logs mapped during this period',
                      style: TextStyle(color: AppColors.slate400))),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingRowHeight: 36,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Commodity')),
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('Units'), numeric: true),
                  DataColumn(label: Text('Revenue'), numeric: true),
                  DataColumn(label: Text('Profit'), numeric: true),
                ],
                rows: [
                  for (var i = 0; i < top.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(top[i]['name'] as String)),
                      DataCell(Text(top[i]['category'] as String)),
                      DataCell(Text('${top[i]['quantity']}')),
                      DataCell(Text(shs(top[i]['revenue'] as num))),
                      DataCell(Text(shs(top[i]['profit'] as num),
                          style:
                              const TextStyle(color: AppColors.emerald))),
                    ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _workerLeaderboard(List<Sale> filtered) {
    final app = context.read<AppState>();
    final counts = <String, Map<String, dynamic>>{};
    for (final s in filtered) {
      counts.putIfAbsent(
          s.cashierId,
          () => {
                'name': s.cashierName,
                'sales': 0 as num,
                'revenue': 0 as num,
                'profit': 0 as num,
              });
      counts[s.cashierId]!['sales'] += 1;
      counts[s.cashierId]!['revenue'] += s.totalAmount;
      counts[s.cashierId]!['profit'] += app.recognizedSaleProfit(s);
    }
    final list = counts.entries.toList()
      ..sort((a, b) =>
          (b.value['profit'] as num).compareTo(a.value['profit'] as num));

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👤 Staff Sales & Profit Leaderboard',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.slate800)),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                  child: Text('No sales logged during this period',
                      style: TextStyle(color: AppColors.slate400))),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingRowHeight: 36,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Staff')),
                  DataColumn(label: Text('ID')),
                  DataColumn(label: Text('Sales'), numeric: true),
                  DataColumn(label: Text('Revenue'), numeric: true),
                  DataColumn(label: Text('Profit'), numeric: true),
                ],
                rows: [
                  for (var i = 0; i < list.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(list[i].value['name'] as String)),
                      DataCell(Text(list[i].key)),
                      DataCell(Text('${list[i].value['sales']}')),
                      DataCell(Text(shs(list[i].value['revenue'] as num))),
                      DataCell(Text(shs(list[i].value['profit'] as num),
                          style:
                              const TextStyle(color: AppColors.emerald))),
                    ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _reportPanel() {
    final report = _activeReport!;
    Map<String, dynamic>? insights;
    try {
      insights = report.aiInsights != null
          ? jsonDecode(report.aiInsights!) as Map<String, dynamic>
          : null;
    } catch (_) {}
    final advice = (insights?['strategicAdvice'] as List?)?.cast<String>() ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppColors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text('EOD BALANCING REPORT - ${report.date}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.indigo)),
            ),
          ]),
          const SizedBox(height: 12),
          const Text('Day successfully balanced. Profit margin locked!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (insights != null) ...[
            Text(insights['eodSummaryText'] as String? ?? '',
                style: const TextStyle(color: AppColors.slate400, fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Strategic Business Insights:',
                style: TextStyle(
                    color: AppColors.indigo,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            const SizedBox(height: 6),
            ...advice.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(color: AppColors.slate400)),
                      Expanded(
                          child: Text(a,
                              style: const TextStyle(
                                  color: AppColors.slate400, fontSize: 12))),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 20, runSpacing: 8, children: [
            _reportStat('Balanced Sales', shs(report.totalSales), Colors.white),
            _reportStat('Staked Capital', shs(report.totalStaked), Colors.white),
            _reportStat(
                'Net Profit', shs(report.totalProfit), AppColors.emerald500),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
              onPressed: () => _sendNotification(insights),
              icon: const Icon(Icons.mail_outline, size: 14),
              label: const Text('Send Summary to Owner'),
            ),
            TextButton(
              onPressed: () => setState(() => _activeReport = null),
              child: const Text('Dismiss',
                  style: TextStyle(color: AppColors.slate400)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _reportStat(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.slate400, fontSize: 11)),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      );
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color bg;
  final Color iconColor;
  _MetricData(this.label, this.value, this.icon, this.bg, this.iconColor);
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.slate500)),
      ]);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
