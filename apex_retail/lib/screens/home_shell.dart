import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

import 'pos_view.dart';

class HomeShell extends StatefulWidget {
  final VoidCallback onLock;
  final String initialTab;
  const HomeShell({super.key, required this.onLock, this.initialTab = 'pos'});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late String _tab = widget.initialTab;
  bool _syncing = false;
  String? _syncMsg;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    // Initial pull + periodic interconnect sync (every 12s) as in the web app.
    _runSync(silent: true);
    _timer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!app.offlineMode) _runSync(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _runSync({bool silent = false}) async {
    final app = context.read<AppState>();
    if (app.offlineMode) {
      if (!silent) {
        setState(() => _syncMsg =
            'Offline Mode is on — working locally. Turn it off to sync with the cloud.');
        _clearMsgLater();
      }
      return;
    }
    if (!silent) setState(() => _syncing = true);
    try {
      final res = await app.triggerSync();
      if (!silent && mounted) {
        setState(() => _syncMsg = res.syncedCount > 0
            ? 'Sync Success! Synced ${res.syncedCount} sales & pulled master updates.'
            : 'Database synchronized with cloud. All terminals aligned.');
      }
    } catch (_) {
      // No internet or the backend is briefly unreachable — this app is
      // designed to keep working offline, so this isn't an error state.
      if (!silent && mounted) {
        setState(() => _syncMsg =
            'No connection right now — working offline. Will sync automatically once back online.');
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _syncing = false);
        _clearMsgLater();
      }
    }
  }

  void _clearMsgLater() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncMsg = null);
    });
  }

  bool _isManagerTab(String t) =>
      t == 'dashboard' || t == 'inventory' || t == 'audit' || t == 'expenses';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isManager = app.isManager;

    // Workers get bounced off manager-only tabs.
    if (!isManager && _isManagerTab(_tab)) {
      // keep on _tab to show the access-denied panel (matches web behavior)
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              syncing: _syncing,
              onManualSync: () => _runSync(),
              onLock: widget.onLock,
            ),
            if (_syncMsg != null)
              Container(
                width: double.infinity,
                color: isManager
                    ? const Color(0xFFEEF2FF)
                    : const Color(0xFF1E1B4B),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Text(_syncMsg!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: isManager
                            ? AppColors.indigo700
                            : const Color(0xFFA5B4FC))),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 760;
                  final nav = _NavRail(
                    active: _tab,
                    isManager: isManager,
                    horizontal: !wide,
                    onSelect: (t) => setState(() => _tab = t),
                    onLock: widget.onLock,
                  );
                  final content = _buildContent(isManager);
                  final collapsed = app.sidebarCollapsed;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!collapsed) SizedBox(width: 220, child: nav),
                        Expanded(child: content),
                      ],
                    );
                  }
                  return Column(children: [
                    if (!collapsed) nav,
                    Expanded(child: content),
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isManager) {
    final bg = isManager ? AppColors.slate50 : AppColors.workerBg;
    Widget child;
    switch (_tab) {
      case 'pos':
        child = const PosView();
        break;
      case 'history':
        child = const SalesLedgerView();
        break;
      case 'dashboard':
        child = isManager
            ? const DashboardView()
            : _denied('The executive analytical profit & loss dashboard is locked for staff shifts.');
        break;
      case 'inventory':
        child = isManager
            ? const InventoryView()
            : _denied('The commodity manager ledger and restock forms are strictly restricted to manager permissions.');
        break;
      case 'audit':
        child = isManager
            ? const AuditLogsView()
            : _denied('The detailed audit log ledger containing shift trails is restricted to security supervisors.');
        break;
      case 'loans':
        child = const LoansView();
        break;
      case 'expenses':
        child = isManager
            ? const ExpensesView()
            : _denied('Business expenditure records are restricted to manager permissions.');
        break;
      case 'settings':
        child = StaffSettingsView(onSessionChange: () => setState(() {
              if (!context.read<AppState>().isManager && _isManagerTab(_tab)) {
                _tab = 'pos';
              }
            }));
        break;
      default:
        child = const PosView();
    }
    return Container(
      color: bg,
      child: SingleChildScrollView(
        padding: Responsive.pagePadding(context),
        child: child,
      ),
    );
  }

  Widget _denied(String msg) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      color: AppColors.slate900, shape: BoxShape.circle),
                  child: const Icon(Icons.gpp_maybe_outlined,
                      color: AppColors.indigo, size: 32),
                ),
                const SizedBox(height: 16),
                const Text('Authorized Access Only',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text(msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.slate400, fontSize: 12)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _tab = 'settings'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald),
                  child: const Text('Switch Shift'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  final bool syncing;
  final VoidCallback onManualSync;
  final VoidCallback onLock;
  const _Header(
      {required this.syncing,
      required this.onManualSync,
      required this.onLock});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isManager = app.isManager;
    final bg = isManager ? Colors.white : AppColors.workerPanel;
    final border = isManager ? AppColors.slate200 : AppColors.slate800;
    final textColor = isManager ? AppColors.slate900 : Colors.white;
    final compact = MediaQuery.sizeOf(context).width < 420;

    // The header's own controls (including the A-/A+ font-scale control
    // itself) must stay a stable, always-tappable size regardless of the
    // app-wide content font scale — otherwise turning the scale up can grow
    // this row until it overflows/misaligns and the control needed to turn
    // it back down becomes unreachable.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.only(left: 4, right: 12, top: 10, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  tooltip: app.sidebarCollapsed ? 'Show menu' : 'Hide menu',
                  onPressed: app.toggleSidebar,
                  icon: Icon(
                    app.sidebarCollapsed ? Icons.menu : Icons.menu_open,
                    color: textColor,
                    size: 22,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: isManager ? AppColors.indigo : AppColors.emerald,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.agriculture_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            AppBranding.businessNameUpper,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isManager
                                      ? AppColors.indigo
                                      : AppColors.emerald)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isManager
                                  ? AppBranding.supervisorPortal
                                  : AppBranding.checkoutStation,
                              style: TextStyle(
                                fontSize: 9,
                                color: isManager
                                    ? AppColors.indigo
                                    : AppColors.emerald,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ]),
                      if (!compact)
                        Text(
                          'INTERCONNECT: ACTIVE • TERMINAL ID: ${app.session.userId}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: isManager
                                ? AppColors.slate500
                                : AppColors.slate400,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Loan alerts bell (overdue + due-soon count).
            _LoanBell(isManager: isManager),
            const SizedBox(width: 8),
            // Font size control.
            _pill(
              isManager,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  onTap: () => app.setFontScale(app.fontScale - 0.1),
                  child: Icon(Icons.text_decrease,
                      size: 15,
                      color:
                          isManager ? AppColors.slate600 : AppColors.slate400),
                ),
                const SizedBox(width: 6),
                Text('${(app.fontScale * 100).round()}%',
                    style: TextStyle(
                        fontSize: 10,
                        color: isManager
                            ? AppColors.slate600
                            : AppColors.slate400)),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => app.setFontScale(app.fontScale + 0.1),
                  child: Icon(Icons.text_increase,
                      size: 15,
                      color:
                          isManager ? AppColors.slate600 : AppColors.slate400),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            _pill(
              isManager,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.circle, size: 6, color: AppColors.indigo),
                const SizedBox(width: 4),
                Text('Synced: ${app.lastSyncTime}',
                    style: TextStyle(
                        fontSize: 10,
                        color: isManager
                            ? AppColors.slate600
                            : AppColors.slate400)),
              ]),
            ),
            const SizedBox(width: 8),
            _pill(
              isManager,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(app.offlineMode ? Icons.wifi_off : Icons.wifi,
                    size: 13,
                    color:
                        app.offlineMode ? AppColors.amber : AppColors.emerald500),
                const SizedBox(width: 5),
                Text(app.offlineMode ? 'Offline' : 'Online',
                    style: TextStyle(
                        fontSize: 10,
                        color: isManager
                            ? AppColors.slate600
                            : AppColors.slate400)),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.65,
                  child: Switch(
                    value: !app.offlineMode,
                    onChanged: (v) => app.setOfflineMode(!v),
                    activeThumbColor: AppColors.emerald,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            _pill(
              isManager,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Queued: ',
                    style: TextStyle(
                        fontSize: 10,
                        color: isManager
                            ? AppColors.slate600
                            : AppColors.slate400)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: app.pendingSyncCount > 0
                        ? AppColors.amber.withValues(alpha: 0.2)
                        : AppColors.emerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${app.pendingSyncCount}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: app.pendingSyncCount > 0
                              ? AppColors.amber600
                              : AppColors.emerald)),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: syncing ? null : onManualSync,
                  child: syncing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.indigo))
                      : Icon(Icons.refresh,
                          size: 13,
                          color: isManager
                              ? AppColors.slate500
                              : AppColors.slate400),
                ),
              ]),
            ),
            if (app.homeSession != null) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => app.switchBack(),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    backgroundColor: const Color(0xFFFFFBEB),
                    foregroundColor: AppColors.amber600),
                icon: const Icon(Icons.swap_horiz, size: 13),
                label: Text('Back to ${app.homeSession!.name}',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
            const SizedBox(width: 8),
            _pill(
              isManager,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: isManager ? AppColors.indigo : AppColors.emerald,
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(app.session.name,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textColor)),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: onLock,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 30),
                      foregroundColor: AppColors.rose),
                  icon: const Icon(Icons.logout, size: 13),
                  label: const Text('Log Out',
                      style:
                          TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
              ]),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _pill(bool isManager, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isManager ? AppColors.slate50 : Colors.black26,
          border: Border.all(
              color: isManager ? AppColors.slate200 : AppColors.slate800),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _NavRail extends StatelessWidget {
  final String active;
  final bool isManager;
  final bool horizontal;
  final ValueChanged<String> onSelect;
  final VoidCallback onLock;
  const _NavRail({
    required this.active,
    required this.isManager,
    required this.horizontal,
    required this.onSelect,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_NavItem>[
      _NavItem('pos', 'POS Terminal', Icons.receipt_long, false),
      _NavItem('history', 'Sales Ledger', Icons.history, false),
      _NavItem('loans', 'Loans & Credit', Icons.account_balance_wallet_outlined, false),
      _NavItem('dashboard', 'Manager Stats', Icons.dashboard_outlined, true),
      _NavItem('inventory', 'Inventory', Icons.inventory_2_outlined, true),
      _NavItem('expenses', 'Expenditures', Icons.payments_outlined, true),
      _NavItem('audit', 'Audit Ledger', Icons.verified_user_outlined, true),
      _NavItem('settings', 'Staff Shifts', Icons.group_outlined, false),
    ];

    // Workers only see modules they can actually open — a locked item with a
    // padlock icon that leads to an access-denied screen isn't useful to show.
    final visibleItems =
        isManager ? items : items.where((it) => !it.managerOnly).toList();

    final buttons = visibleItems
        .map((it) => _navButton(it))
        .toList();

    if (horizontal) {
      return Container(
        color: isManager ? Colors.white : AppColors.workerPanel,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final b in buttons) Padding(padding: const EdgeInsets.only(right: 6), child: b),
            _logoutButton(),
          ]),
        ),
      );
    }

    return Container(
      color: isManager ? Colors.white : AppColors.workerPanel,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 6, 6, 10),
            child: Text('SHIFT MODULES',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.slate400)),
          ),
          for (final b in buttons)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: b),
          const Spacer(),
          _logoutButton(),
        ],
      ),
    );
  }

  Widget _navButton(_NavItem it) {
    final isActive = active == it.id;
    final locked = it.managerOnly && !isManager;
    final activeColor = isManager ? AppColors.indigo : AppColors.emerald;
    final fg = isActive
        ? Colors.white
        : (isManager ? AppColors.slate600 : AppColors.slate400);
    return Material(
      color: isActive ? activeColor : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(it.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(it.icon, size: 16, color: fg),
              const SizedBox(width: 10),
              // In the vertical rail width is bounded, so let the label shrink;
              // in the horizontal scroller width is unbounded, so keep natural.
              if (horizontal)
                Text(it.label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: fg))
              else
                Flexible(
                  child: Text(it.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: fg)),
                ),
              if (locked) ...[
                const SizedBox(width: 6),
                const Icon(Icons.lock, size: 12, color: AppColors.slate500),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoutButton() => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onLock,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.logout, size: 16, color: AppColors.rose),
              SizedBox(width: 10),
              Text('Log Out',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.rose)),
            ]),
          ),
        ),
      );
}

class _NavItem {
  final String id;
  final String label;
  final IconData icon;
  final bool managerOnly;
  _NavItem(this.id, this.label, this.icon, this.managerOnly);
}

/// Bell badge summarizing overdue + due-soon loans; tapping shows a quick list.
class _LoanBell extends StatelessWidget {
  final bool isManager;
  const _LoanBell({required this.isManager});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final overdue = app.overdueLoans.length;
    final dueSoon = app.dueSoonLoans.length;
    final count = overdue + dueSoon;
    return InkWell(
      onTap: () => _showLoans(context, app),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isManager ? AppColors.slate50 : Colors.black26,
          border: Border.all(
              color: isManager ? AppColors.slate200 : AppColors.slate800),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.notifications_active_outlined,
              size: 15,
              color: count > 0
                  ? (overdue > 0 ? AppColors.rose : AppColors.amber600)
                  : (isManager ? AppColors.slate500 : AppColors.slate400)),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: overdue > 0 ? AppColors.rose : AppColors.amber600,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      ),
    );
  }

  void _showLoans(BuildContext context, AppState app) {
    final overdue = app.overdueLoans;
    final dueSoon = app.dueSoonLoans;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Loan Alerts'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: Responsive.dialogWidth(context, max: 380)),
          child: (overdue.isEmpty && dueSoon.isEmpty)
              ? const Text('No loans are overdue or due soon. 🎉')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in overdue)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.error_outline,
                              color: AppColors.rose),
                          title: Text(l.customerName),
                          subtitle: Text(
                              'OVERDUE since ${l.pledgeDate} • balance shs ${l.balance}'),
                        ),
                      for (final l in dueSoon)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule,
                              color: AppColors.amber600),
                          title: Text(l.customerName),
                          subtitle: Text(
                              'Due ${l.pledgeDate} (${l.daysUntilDue()}d) • balance shs ${l.balance}'),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
