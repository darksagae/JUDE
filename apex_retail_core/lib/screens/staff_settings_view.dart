import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/responsive.dart';
import 'package:apex_retail_core/utils/print_service.dart';

class StaffSettingsView extends StatefulWidget {
  final VoidCallback onSessionChange;
  const StaffSettingsView({super.key, required this.onSessionChange});
  @override
  State<StaffSettingsView> createState() => _StaffSettingsViewState();
}

class _StaffSettingsViewState extends State<StaffSettingsView> {
  final _newName = TextEditingController();
  UserRole _newRole = UserRole.worker;
  final _newPass = TextEditingController();
  final Map<String, bool> _visible = {};

  // Kept as State fields (not created inline in _workerPasswordCard) so
  // typing survives a parent rebuild — e.g. the periodic background sync
  // notifying AppState — instead of being wiped by fresh controllers on
  // every rebuild.
  final _pwCurrent = TextEditingController();
  final _pwNew = TextEditingController();
  final _pwConfirm = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    _newPass.dispose();
    _pwCurrent.dispose();
    _pwNew.dispose();
    _pwConfirm.dispose();
    super.dispose();
  }

  void _snack(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? AppColors.rose : AppColors.emerald,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isTop = app.session.role == UserRole.topManager;
    final isWorker = app.session.role == UserRole.worker;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final left = Column(children: [
        _sessionHeader(app),
        const SizedBox(height: 16),
        _staffDirectory(app, isTop),
      ]);
      final right = Column(children: [
        if (!isWorker) ...[
          _printerCard(app),
          const SizedBox(height: 16),
        ],
        if (isWorker) _workerPasswordCard(app),
        if (!isWorker) _registerCard(app, isTop),
      ]);
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: left),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: right),
          ],
        );
      }
      return Column(children: [left, const SizedBox(height: 16), right]);
    });
  }

  Widget _card({required Widget child, Color? color, Color? border}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border ?? AppColors.slate100),
        ),
        child: child,
      );

  Widget _sessionHeader(AppState app) {
    final role = app.session.role;
    final color = role == UserRole.topManager
        ? AppColors.amber
        : role == UserRole.manager
            ? AppColors.indigo
            : AppColors.emerald;
    return _card(
      color: AppColors.slate900,
      border: AppColors.slate800,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(
              role == UserRole.topManager
                  ? Icons.verified_user
                  : Icons.person,
              color: color,
              size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CURRENT SESSION SHIFT',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate400)),
              Text(
                  app.session.role == UserRole.topManager
                      ? app.session.name
                      : '${app.session.name} (${app.session.userId})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(20)),
                child: Text(role.label.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        if (role == UserRole.topManager)
          TextButton.icon(
            onPressed: () => _editMyAccount(app),
            style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            icon: const Icon(Icons.manage_accounts, size: 16),
            label: const Text('My Account', style: TextStyle(fontSize: 11)),
          ),
      ]),
    );
  }

  /// Lets the top manager change their own login name, User ID, and PIN.
  /// Authorized by re-entering the current PIN. Changing the User ID moves the
  /// authoritative row in Neon (old id deleted, new id created) via setStaff and
  /// re-issues the new id so it is never handed to anyone else.
  void _editMyAccount(AppState app) {
    final me = app.staff
        .where((s) => s.userId == app.session.userId)
        .cast<StaffProfile?>()
        .firstOrNull;
    if (me == null) {
      _snack('Your account record could not be found.', err: true);
      return;
    }
    final name = TextEditingController(text: me.name);
    final id = TextEditingController(text: me.userId);
    final currentPin = TextEditingController();
    final newPin = TextEditingController();
    final confirmPin = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My Account'),
        content: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: Responsive.dialogWidth(ctx, max: 420)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Update your display name, login ID, or PIN. Re-enter your '
                    'current PIN to authorize the change.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate500)),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: id,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'Login User ID',
                      helperText: 'Used with your PIN to sign in.'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: currentPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Current PIN *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'New PIN (leave blank to keep current)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Confirm New PIN'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.slate900),
            onPressed: () {
              final newName = name.text.trim();
              final newId = id.text.trim().toUpperCase();
              if (currentPin.text.trim() != me.passcode) {
                _snack('Incorrect current PIN.', err: true);
                return;
              }
              if (newName.isEmpty) {
                _snack('Name cannot be empty.', err: true);
                return;
              }
              if (newId.isEmpty) {
                _snack('Login User ID cannot be empty.', err: true);
                return;
              }
              // Guard against colliding with another existing account's ID.
              if (newId != me.userId &&
                  app.staff.any((s) => s.userId == newId)) {
                _snack('User ID "$newId" is already in use.', err: true);
                return;
              }
              var pass = me.passcode;
              if (newPin.text.trim().isNotEmpty) {
                if (newPin.text.trim() != confirmPin.text.trim()) {
                  _snack('Confirm PIN does not match.', err: true);
                  return;
                }
                pass = newPin.text.trim();
              }
              final updatedProfile = StaffProfile(
                  userId: newId,
                  name: newName,
                  role: me.role,
                  passcode: pass);
              final updated = app.staff
                  .map((s) => s.userId == me.userId ? updatedProfile : s)
                  .toList();
              app.setStaff(updated);
              if (newId != me.userId) {
                app.registerIssuedId(newId);
              }
              app.setSession(
                  UserSession(
                      userId: newId, name: newName, role: me.role),
                  logLogin: false);
              app.logAction(newId, newName, me.role, 'PROFILE_UPDATE',
                  'Top Manager updated own account (name/ID/PIN). ID ${me.userId} → $newId.');
              Navigator.pop(ctx);
              _snack('Your account has been updated.');
              widget.onSessionChange();
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Widget _staffDirectory(AppState app, bool isTop) {
    final isManager = app.session.role.isManagerial;
    // Hierarchy visibility: Top Manager sees everyone. A Manager sees
    // everyone except Top Manager (invisible entirely, not just
    // credential-masked). A Worker sees only fellow Workers — a manager or
    // top manager logging in should not be visible to them at all.
    final visibleStaff = isTop
        ? app.staff
        : isManager
            ? app.staff.where((m) => m.role != UserRole.topManager).toList()
            : app.staff.where((m) => m.role == UserRole.worker).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Staff Directory',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.slate900)),
            ),
            Text('${visibleStaff.length} Accounts',
                style: const TextStyle(fontSize: 11, color: AppColors.slate500)),
          ]),
          const SizedBox(height: 12),
          ...visibleStaff.map((m) => _staffRow(app, m, isTop, isManager)),
        ],
      ),
    );
  }

  Widget _staffRow(
      AppState app, StaffProfile m, bool isTop, bool isManager) {
    final isSelf = m.userId == app.session.userId;
    final isTargetWorker = m.role == UserRole.worker;
    final isTargetTop = m.role == UserRole.topManager;
    // The top manager's own ID and PIN stay hidden even from themselves, so a
    // glance at a shared screen can't leak the master credentials. They still
    // see every other account's details.
    final hideOwnCreds = isSelf && app.session.role == UserRole.topManager;
    final canSee =
        !hideOwnCreds && (isTop || (isManager && isTargetWorker) || isSelf);
    // Top Manager can switch into any other account. A Manager can switch
    // into any account except Top Manager (workers and other managers).
    final canImpersonate =
        !isSelf && (isTop || (isManager && !isTargetTop));
    final canModify = isTop && !isTargetTop;
    // Password resets flow down the hierarchy: a top manager may reset managers
    // and workers; a manager may reset workers.
    final canChangePass = !isSelf &&
        ((isTop && !isTargetTop) || (isManager && !isTop && isTargetWorker));
    final visible = _visible[m.userId] ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.slate100))),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: isTargetTop
                      ? const Color(0xFFFFFBEB)
                      : isTargetWorker
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(
                  isTargetTop ? Icons.verified_user : Icons.person,
                  size: 18,
                  color: isTargetTop
                      ? AppColors.amber600
                      : isTargetWorker
                          ? AppColors.emerald
                          : AppColors.indigo),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(m.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (isSelf) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                          color: AppColors.slate100,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('YOU',
                          style: TextStyle(
                              fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                Text(
                    'ID: ${hideOwnCreds ? '••••••' : m.userId} • ${m.role.wire.replaceAll('_', ' ')}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.slate400)),
              ],
            ),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.vpn_key, size: 12, color: AppColors.slate400),
                const SizedBox(width: 4),
                Text(
                    canSee
                        ? (visible ? m.passcode : '••••')
                        : '•••• (Protected)',
                    style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: AppColors.slate500)),
                if (canSee)
                  InkWell(
                    onTap: () =>
                        setState(() => _visible[m.userId] = !visible),
                    child: Icon(
                        visible ? Icons.visibility_off : Icons.visibility,
                        size: 12,
                        color: AppColors.slate400),
                  ),
              ]),
            ),
            if (canModify) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => _toggleRole(app, m),
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(
                    m.role == UserRole.manager
                        ? 'Demote'
                        : 'Promote',
                    style: const TextStyle(fontSize: 10)),
              ),
            ],
            if (canImpersonate) ...[
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.indigo,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => _impersonate(app, m),
                child: const Text('Open', style: TextStyle(fontSize: 10)),
              ),
            ],
            if (canChangePass) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Reset PIN',
                icon: const Icon(Icons.lock_reset,
                    size: 18, color: AppColors.indigo),
                onPressed: () => _changeStaffPassword(app, m),
              ),
            ],
            if (canModify) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: AppColors.slate400),
                onPressed: () => _deleteStaff(app, m),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  void _impersonate(AppState app, StaffProfile m) {
    app.logAction(app.session.userId, app.session.name, app.session.role,
        'IMPERSONATE',
        'Direct session shift opened for user: ${m.name} (ID: ${m.userId})');
    app.setSession(
        UserSession(userId: m.userId, name: m.name, role: m.role),
        logLogin: false);
    widget.onSessionChange();
  }

  void _toggleRole(AppState app, StaffProfile m) {
    if (m.role == UserRole.topManager) return;
    final newRole =
        m.role == UserRole.manager ? UserRole.worker : UserRole.manager;
    final updated = app.staff.map((s) {
      if (s.userId == m.userId) {
        return StaffProfile(
            userId: s.userId,
            name: s.name,
            role: newRole,
            passcode: s.passcode);
      }
      return s;
    }).toList();
    app.setStaff(updated);
    app.logAction(app.session.userId, app.session.name, app.session.role,
        'STAFF_ROLE_CHANGE',
        'Toggled role of ${m.name} (${m.userId}) to ${newRole.wire}');
  }

  void _deleteStaff(AppState app, StaffProfile m) {
    if (m.role == UserRole.topManager) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Remove staff member ${m.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () {
              app.setStaff(
                  app.staff.where((s) => s.userId != m.userId).toList());
              app.logAction(app.session.userId, app.session.name,
                  app.session.role, 'STAFF_REMOVE',
                  'Removed staff profile of ${m.name} (${m.userId})');
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _changeStaffPassword(AppState app, StaffProfile m) {
    final newP = TextEditingController();
    final confirm = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset PIN — ${m.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Set a new passcode for ${m.name} (${m.role.wire.replaceAll('_', ' ')}). They will use it at their next sign-in.',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.slate500)),
            const SizedBox(height: 12),
            TextField(
              controller: newP,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'New PIN'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Confirm New PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final np = newP.text.trim();
              if (np.isEmpty) {
                _snack('New PIN cannot be empty.', err: true);
                return;
              }
              if (np != confirm.text.trim()) {
                _snack('Confirm PIN does not match.', err: true);
                return;
              }
              final updated = app.staff.map((s) {
                if (s.userId == m.userId) {
                  return StaffProfile(
                      userId: s.userId,
                      name: s.name,
                      role: s.role,
                      passcode: np);
                }
                return s;
              }).toList();
              app.setStaff(updated);
              app.logAction(app.session.userId, app.session.name,
                  app.session.role, 'PASSWORD_RESET',
                  'Reset PIN for ${m.name} (${m.userId}) under hierarchy authority');
              Navigator.pop(ctx);
              _snack('PIN reset for ${m.name}.');
            },
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
  }

  Widget _printerCard(AppState app) {
    final s = app.printerSettings;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.print, size: 16, color: AppColors.slate400),
            SizedBox(width: 8),
            Text('POS HARDWARE PRINTER',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800)),
          ]),
          const SizedBox(height: 12),
          _kvRow('Paper Width', s.paperWidth),
          _kvRow('Default Format', s.defaultFormat),
          _kvRow('IP Address', s.ipAddress.isEmpty ? 'Not Configured' : s.ipAddress),
          _kvRow('BT MAC', s.bluetoothAddress.isEmpty ? 'Not Configured' : s.bluetoothAddress),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.slate900),
              onPressed: () => _openPrinterConsole(app),
              icon: const Icon(Icons.tune, size: 14),
              label: const Text('Open Printer Console'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.slate500)),
            Flexible(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  void _openPrinterConsole(AppState app) {
    var paper = app.printerSettings.paperWidth;
    var format = app.printerSettings.defaultFormat;
    final ip = TextEditingController(text: app.printerSettings.ipAddress);
    final bt = TextEditingController(text: app.printerSettings.bluetoothAddress);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        Widget toggle(String label, String value, String current,
                VoidCallback onTap) =>
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: current == value
                        ? AppColors.slate900
                        : AppColors.slate50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: current == value
                              ? Colors.white
                              : AppColors.slate600)),
                ),
              ),
            );

        return AlertDialog(
          title: const Text('Printer Configuration Console'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 400)),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Thermal Paper Dimensions',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(height: 6),
                Row(children: [
                  toggle('58mm', '58mm', paper,
                      () => setModal(() => paper = '58mm')),
                  toggle('80mm', '80mm', paper,
                      () => setModal(() => paper = '80mm')),
                ]),
                const SizedBox(height: 12),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Default Format',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold))),
                const SizedBox(height: 6),
                Row(children: [
                  toggle('Receipt', 'receipt', format,
                      () => setModal(() => format = 'receipt')),
                  toggle('Sticker', 'sticker', format,
                      () => setModal(() => format = 'sticker')),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: ip,
                  decoration: const InputDecoration(
                      labelText: 'Printer Address (IP / hostname / .local)',
                      prefixIcon: Icon(Icons.wifi, size: 16)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bt,
                  decoration: const InputDecoration(
                      labelText: 'Bluetooth MAC/UUID',
                      prefixIcon: Icon(Icons.bluetooth, size: 16)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => PrintService.printTest(PrinterSettings(
                        paperWidth: paper,
                        ipAddress: ip.text.trim(),
                        bluetoothAddress: bt.text.trim(),
                        defaultFormat: format)),
                    icon: const Icon(Icons.print, size: 14),
                    label: const Text('Send Hardware Test Print'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                // Accept any printer address — IPv4, hostname, mDNS (.local) or
                // a Bluetooth device — so the app is not tied to one kind of
                // network or device.
                final cleanIp = ip.text.trim();
                app.setPrinterSettings(PrinterSettings(
                    paperWidth: paper,
                    defaultFormat: format,
                    ipAddress: cleanIp,
                    bluetoothAddress: bt.text.trim()));
                app.logAction(app.session.userId, app.session.name,
                    app.session.role, 'PRINTER_CONFIG_SET',
                    'Printer settings updated: paperWidth=$paper, format=$format');
                Navigator.pop(ctx);
                _snack('Printer settings applied.');
              },
              child: const Text('Save & Apply'),
            ),
          ],
        );
      }),
    );
  }

  Widget _workerPasswordCard(AppState app) {
    final current = _pwCurrent;
    final newP = _pwNew;
    final confirm = _pwConfirm;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.vpn_key, size: 16, color: AppColors.emerald),
            SizedBox(width: 8),
            Text('CHANGE MY PIN',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current PIN')),
          const SizedBox(height: 8),
          TextField(
              controller: newP,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New PIN')),
          const SizedBox(height: 8),
          TextField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm New PIN')),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.slate900),
              onPressed: () {
                final profile = app.staff
                    .where((s) => s.userId == app.session.userId)
                    .cast<StaffProfile?>()
                    .firstOrNull;
                if (profile == null) return;
                if (current.text != profile.passcode) {
                  _snack('Incorrect current passcode.', err: true);
                  return;
                }
                if (newP.text.trim().isEmpty) {
                  _snack('New passcode cannot be empty.', err: true);
                  return;
                }
                if (newP.text != confirm.text) {
                  _snack('Confirm passcode does not match.', err: true);
                  return;
                }
                final updated = app.staff.map((s) {
                  if (s.userId == app.session.userId) {
                    return StaffProfile(
                        userId: s.userId,
                        name: s.name,
                        role: s.role,
                        passcode: newP.text.trim());
                  }
                  return s;
                }).toList();
                app.setStaff(updated);
                app.logAction(app.session.userId, app.session.name,
                    app.session.role, 'PASSWORD_CHANGE',
                    'Staff changed their password securely');
                current.clear();
                newP.clear();
                confirm.clear();
                _snack('Your shift password has been updated!');
              },
              child: const Text('Change PIN Code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerCard(AppState app, bool isTop) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.person_add_alt, size: 16, color: AppColors.slate400),
            SizedBox(width: 8),
            Text('REGISTER NEW STAFF',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          TextField(
              controller: _newName,
              decoration: const InputDecoration(labelText: 'Full Name')),
          const SizedBox(height: 8),
          if (isTop)
            DropdownButtonFormField<UserRole>(
              initialValue: _newRole,
              decoration:
                  const InputDecoration(labelText: 'System Access Level'),
              items: const [
                DropdownMenuItem(
                    value: UserRole.worker,
                    child: Text('Staff (Checkout POS)')),
                DropdownMenuItem(
                    value: UserRole.manager,
                    child: Text('Manager (Full Dashboard)')),
              ],
              onChanged: (v) => setState(() => _newRole = v ?? UserRole.worker),
            ),
          const SizedBox(height: 8),
          TextField(
              controller: _newPass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passcode PIN')),
          const SizedBox(height: 6),
          const Text(
              'A sequential account ID is assigned automatically and never reused.',
              style: TextStyle(fontSize: 10, color: AppColors.slate400)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.indigo),
              onPressed: () => _createStaff(app, isTop),
              icon: const Icon(Icons.person_add_alt, size: 14),
              label: const Text('Save Staff Member'),
            ),
          ),
        ],
      ),
    );
  }

  void _createStaff(AppState app, bool isTop) {
    final name = _newName.text.trim();
    final pass = _newPass.text.trim();
    if (name.isEmpty || pass.isEmpty) {
      _snack('Name and passcode are required.', err: true);
      return;
    }
    final role = isTop ? _newRole : UserRole.worker;
    // IDs are allocated in sequence and never reused (handled by AppState).
    final id = app.nextStaffId(role);
    app.setStaff([
      ...app.staff,
      StaffProfile(userId: id, name: name, role: role, passcode: pass)
    ]);
    app.logAction(app.session.userId, app.session.name, app.session.role,
        'STAFF_ADD', 'Registered new ${role.wire} account: $name (ID: $id)');
    _newName.clear();
    _newPass.clear();
    _snack('Successfully registered $name ($id)!');
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
