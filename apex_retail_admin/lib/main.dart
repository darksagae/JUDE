import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

import 'screens/login_screen.dart';
import 'screens/admin_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(JudeFarmSupplyAdminApp(app: app));
}

class JudeFarmSupplyAdminApp extends StatelessWidget {
  final AppState app;
  const JudeFarmSupplyAdminApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        title: AppBranding.adminAppTitle,
        debugShowCheckedModeBanner: false,
        theme: managerTheme(),
        // Fixed at the default medium font size — no per-account adjustment.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: const _AdminRoot(),
      ),
    );
  }
}

class _AdminRoot extends StatefulWidget {
  const _AdminRoot();
  @override
  State<_AdminRoot> createState() => _AdminRootState();
}

class _AdminRootState extends State<_AdminRoot> {
  bool _locked = true;
  String? _denied;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (_locked) {
      return Theme(
        data: workerTheme(),
        child: Stack(children: [
          LoginScreen(
            app: app,
            onLoginSuccess: () {
              if (app.session.role == UserRole.topManager) {
                setState(() {
                  _locked = false;
                  _denied = null;
                });
              } else {
                // A non-Top-Manager account was authenticated by the login
                // form itself — don't leave AppState.session pointed at it
                // while this console stays locked.
                app.logout();
                setState(() => _denied =
                    'This is the Top-Admin console. Only Top Manager accounts (e.g. TM001) may sign in here.');
              }
            },
          ),
          if (_denied != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.rose,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_denied!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),
        ]),
      );
    }

    return Theme(
      data: managerTheme(),
      child: AdminShell(
        onLock: () {
          app.logout();
          setState(() => _locked = true);
        },
      ),
    );
  }
}
