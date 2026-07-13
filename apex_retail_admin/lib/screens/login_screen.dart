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
    if (match.role != UserRole.topManager) {
      setState(() => _error =
          'Only Top Manager accounts may access this console.');
      return;
    }
    if (pass == match.passcode) {
      widget.app.setSession(
          UserSession(userId: match.userId, name: match.name, role: match.role));
      widget.app.logAction(match.userId, match.name, match.role, 'LOGIN',
          'Admin console authenticated');
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
                      color: AppColors.amber600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(AppBranding.loginAdminTitle,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  const Text(AppBranding.loginAdminSubtitle,
                      style: TextStyle(color: AppColors.slate400, fontSize: 12)),
                  const SizedBox(height: 22),
                  _label('Top Manager Credentials'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _id,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                      hintText: 'Enter your Top Manager ID',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('Top Manager Passcode'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _pass,
                    obscureText: !_show,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _busy ? null : _login(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                      hintText: 'Enter Top Manager passcode',
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
                        backgroundColor: AppColors.amber600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(_busy ? 'VERIFYING…' : 'AUTHENTICATE',
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
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
