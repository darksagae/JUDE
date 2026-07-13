// Boots the full app shell and navigates every screen to ensure they build.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apex_retail_core/apex_retail_core.dart';
import 'package:apex_retail/screens/home_shell.dart';

Future<AppState> _bootManager() async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState();
  await app.init();
  app.setSession(
      UserSession(userId: 'M001', name: 'Alex Mercer', role: UserRole.manager),
      logLogin: false);
  return app;
}

Widget _wrap(AppState app) => ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: managerTheme(),
        home: HomeShell(onLock: () {}),
      ),
    );

void main() {
  testWidgets('Manager shell boots on POS', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final app = await _bootManager();
    // The system ships with no demo data; add a product so the shell renders
    // with real content.
    app.setOfflineMode(true);
    app.addProduct(
      name: 'Test Maize',
      sku: '',
      category: 'Seeds',
      buyingPrice: 100,
      currentStock: 10,
      minStockLevel: 2,
      expirationDate: null,
    );
    expect(app.products.length, greaterThan(0));

    await tester.pumpWidget(_wrap(app));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(AppBranding.businessNameUpper), findsOneWidget);
    expect(find.text('Active Checkout'), findsOneWidget); // POS cart panel
  });

  testWidgets('All manager tabs build without error', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final app = await _bootManager();
    await tester.pumpWidget(_wrap(app));
    await tester.pump(const Duration(milliseconds: 300));

    for (final tab in [
      'Sales Ledger',
      'Loans & Credit',
      'Manager Stats',
      'Inventory',
      'Expenditures',
      'Audit Ledger',
      'Staff Shifts',
      'POS Terminal',
    ]) {
      await tester.tap(find.text(tab).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'Tab "$tab" threw');
    }
  });
}
