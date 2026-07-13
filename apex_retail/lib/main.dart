import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(JudeFarmSupplyApp(app: app));
}

class JudeFarmSupplyApp extends StatelessWidget {
  final AppState app;
  const JudeFarmSupplyApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        title: AppBranding.terminalAppTitle,
        debugShowCheckedModeBanner: false,
        theme: managerTheme(),
        // Fixed at the default medium font size — no per-account adjustment.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _locked = true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_locked) {
      return Theme(
        data: workerTheme(),
        child: LoginScreen(
          app: app,
          onLoginSuccess: () => setState(() => _locked = false),
        ),
      );
    }
    return Theme(
      data: app.isManager ? managerTheme() : workerTheme(),
      child: HomeShell(
        onLock: () {
          app.logout();
          setState(() => _locked = true);
        },
      ),
    );
  }
}
