import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

class AdminShell extends StatefulWidget {
  final VoidCallback onLock;
  const AdminShell({super.key, required this.onLock});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  Timer? _timer;
  bool _syncing = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _tabs = [
    _AdminTab('Overview', Icons.dashboard_outlined),
    _AdminTab('Sales', Icons.receipt_long),
    _AdminTab('Loans', Icons.account_balance_wallet_outlined),
    _AdminTab('Expenditures', Icons.payments_outlined),
    _AdminTab('Inventory', Icons.inventory_2_outlined),
    _AdminTab('Staff & Accounts', Icons.group_outlined),
    _AdminTab('Audit', Icons.verified_user_outlined),
  ];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!app.offlineMode) _sync(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sync({bool silent = false}) async {
    final app = context.read<AppState>();
    if (app.offlineMode) return;
    if (!silent) setState(() => _syncing = true);
    try {
      await app.triggerSync();
    } catch (_) {}
    if (!silent && mounted) setState(() => _syncing = false);
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    _scaffoldKey.currentState?.closeDrawer();
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return const DashboardView();
      case 1:
        return const SalesLedgerView();
      case 2:
        return const LoansView();
      case 3:
        return const ExpensesView();
      case 4:
        return const InventoryView();
      case 5:
        return StaffSettingsView(onSessionChange: () => setState(() {}));
      case 6:
        return const AuditLogsView();
      default:
        return const DashboardView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= Responsive.tablet;
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.slate50,
        drawer: wide
            ? null
            : Drawer(child: SafeArea(child: _rail(app, inDrawer: true))),
        body: SafeArea(
          child: wide
              ? Row(children: [
                  _rail(app),
                  Expanded(child: _mainColumn(app, mobile: false)),
                ])
              : _mainColumn(app, mobile: true),
        ),
      );
    });
  }

  Widget _mainColumn(AppState app, {required bool mobile}) {
    return Column(
      children: [
        _topBar(app, mobile: mobile),
        Expanded(
          child: SingleChildScrollView(
            padding: Responsive.pagePadding(context),
            child: _body(),
          ),
        ),
      ],
    );
  }

  Widget _rail(AppState app, {bool inDrawer = false}) {
    return Container(
      width: inDrawer ? null : 230,
      color: AppColors.slate900,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.amber600,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.shield, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(AppBranding.adminRailTitle,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.5)),
            ),
          ]),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(AppBranding.adminRailSubtitle,
                style: TextStyle(color: AppColors.slate400, fontSize: 10)),
          ),
          for (var i = 0; i < _tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: _index == i ? AppColors.amber600 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _selectTab(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    child: Row(children: [
                      Icon(_tabs[i].icon,
                          size: 16,
                          color: _index == i
                              ? Colors.white
                              : AppColors.slate400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_tabs[i].label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _index == i
                                    ? Colors.white
                                    : AppColors.slate400)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: widget.onLock,
            icon: const Icon(Icons.logout, size: 15, color: AppColors.rose),
            label: const Text('Log Out',
                style: TextStyle(color: AppColors.rose, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _topBar(AppState app, {required bool mobile}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.slate200)),
      ),
      padding: EdgeInsets.symmetric(
          horizontal: mobile ? 8 : 20, vertical: mobile ? 8 : 12),
      child: Row(children: [
        if (mobile)
          IconButton(
            tooltip: 'Menu',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu, size: 22),
          ),
        Expanded(
          child: Text(_tabs[_index].label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: mobile ? 15 : 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.slate800)),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _syncing ? null : () => _sync(),
          icon: _syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 18),
        ),
        if (!mobile && app.homeSession != null) ...[
          TextButton.icon(
            onPressed: () => app.switchBack(),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                backgroundColor: const Color(0xFFEEF2FF),
                foregroundColor: AppColors.indigo),
            icon: const Icon(Icons.swap_horiz, size: 14),
            label: Text('Back to ${app.homeSession!.name}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
        if (!mobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.verified_user,
                  size: 14, color: AppColors.amber600),
              const SizedBox(width: 6),
              Text(app.session.name,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.amber600.withValues(alpha: 0.15),
              child: Text(
                app.session.name.isNotEmpty
                    ? app.session.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.amber600),
              ),
            ),
          ),
      ]),
    );
  }
}

class _AdminTab {
  final String label;
  final IconData icon;
  const _AdminTab(this.label, this.icon);
}
