import 'package:flutter/material.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

class LoginScreen extends StatefulWidget {
  final AppState app;
  final VoidCallback onLoginSuccess;
  const LoginScreen(
      {super.key, required this.app, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserRole _role = UserRole.worker;
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool _busy = false;

  Future<void> _login() async {
    setState(() => _error = null);
    final id = _id.text.trim().toUpperCase();
    final pass = _pass.text.trim();
    if (id.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in both User ID and passcode.');
      return;
    }
    // Pull the authoritative staff directory from Neon first so we validate
    // against the cloud, not a stale locally-cached PIN. No-op when offline.
    setState(() => _busy = true);
    await widget.app.refreshStaff();
    if (!mounted) return;
    setState(() => _busy = false);
    final match = widget.app.staff
        .where((s) => s.userId == id)
        .cast<StaffProfile?>()
        .firstOrNull;
    if (match == null) {
      setState(() => _error = 'No registered staff member found with ID: $id');
      return;
    }
    if (match.role == UserRole.topManager) {
      setState(() => _error =
          'Top Manager accounts must use the judefarmsupply admin app, not this terminal.');
      return;
    }
    if (match.role != _role) {
      setState(() => _error =
          'Staff member ${match.name} is a ${match.role.wire.replaceAll('_', ' ')}. Please select the correct role above.');
      return;
    }
    if (pass == match.passcode) {
      widget.app.setSession(
          UserSession(userId: match.userId, name: match.name, role: match.role));
      widget.app.logAction(match.userId, match.name, match.role, 'LOGIN',
          'Shift authenticated successfully as ${match.role.wire.replaceAll('_', ' ')}');
      widget.onLoginSuccess();
    } else {
      setState(() => _error = 'Incorrect security passcode.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate950,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.slate900,
                border: Border.all(color: AppColors.slate800),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.indigo, Color(0xFF7C3AED)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.agriculture_outlined,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(AppBranding.loginTerminalTitle,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  const Text(AppBranding.loginTerminalSubtitle,
                      style: TextStyle(color: AppColors.slate400, fontSize: 12)),
                  const SizedBox(height: 22),
                  _roleTabs(),
                  const SizedBox(height: 20),
                  _label('Staff ID Credentials'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _id,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                      hintText: 'Enter your staff ID',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label(_role == UserRole.manager
                      ? 'Manager Passcode'
                      : 'Staff PIN Code'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _pass,
                    obscureText: !_show,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _busy ? null : _login(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                      hintText: _role == UserRole.manager
                          ? 'Enter manager passcode'
                          : 'Enter staff PIN',
                      suffixIcon: IconButton(
                        icon: Icon(
                            _show ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                            color: AppColors.slate400),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.1),
                        border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        const Icon(Icons.gpp_maybe_outlined,
                            color: AppColors.red, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.red, fontSize: 12))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _login,
                      style: FilledButton.styleFrom(
                        backgroundColor: _role == UserRole.manager
                            ? AppColors.indigo
                            : AppColors.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(_busy ? 'VERIFYING…' : 'AUTHENTICATE SHIFT',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Align(
        alignment: Alignment.centerLeft,
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: AppColors.slate400,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );

  Widget _roleTabs() {
    Widget tab(UserRole r, String label, IconData icon, Color color) {
      final active = _role == r;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _role = r;
            _error = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 13,
                    color: active ? Colors.white : AppColors.slate400),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : AppColors.slate400)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.slate950,
        border: Border.all(color: AppColors.slate800),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        tab(UserRole.worker, 'Staff', Icons.person_outline, AppColors.emerald),
        tab(UserRole.manager, 'Manager', Icons.verified_user_outlined,
            AppColors.indigo),
      ]),
    );
  }

}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
