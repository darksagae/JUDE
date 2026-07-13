// Verifies the new business rules: price floor, cash+loan split, loan
// repayment, and expenditure recording.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apex_retail_core/apex_retail_core.dart';

Future<AppState> boot() async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState();
  await app.init();
  app.setSession(
      UserSession(userId: 'M001', name: 'Alex Mercer', role: UserRole.manager),
      logLogin: false);
  return app;
}

void main() {
  // Initialize the binding so plugin channels (e.g. connectivity) are stubbed
  // instead of throwing when AppState.init() starts its network watcher.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selling price cannot go below the floor', () async {
    final app = await boot();
    final p = app.addProduct(
      name: 'Test Item',
      sku: '',
      category: 'Snacks',
      buyingPrice: 1000,
      sellingPrice: 800, // below floor
      wholesalePrice: 1200,
      currentStock: 5,
      minStockLevel: 1,
      expirationDate: null,
    );
    // Constructor clamps up to the floor.
    expect(p.sellingPrice, 1200);

    // Editing below floor also clamps.
    final edited = p.copy()..sellingPrice = 900;
    app.updateProduct(edited);
    expect(app.products.firstWhere((x) => x.id == p.id).sellingPrice, 1200);

    // Above floor is accepted (no max).
    final up = p.copy()..sellingPrice = 999999;
    app.updateProduct(up);
    expect(app.products.firstWhere((x) => x.id == p.id).sellingPrice, 999999);
  });

  test('cash + loan split creates a loan for the remainder', () async {
    final app = await boot();
    app.setOfflineMode(true);
    final prod = app.addProduct(
      name: 'Test Item',
      sku: '',
      category: 'Seeds',
      buyingPrice: 100,
      sellingPrice: 1000,
      wholesalePrice: 100,
      currentStock: 5,
      minStockLevel: 1,
      expirationDate: null,
    );
    final item = SaleItem(
      id: 'i1',
      productId: prod.id,
      productName: prod.name,
      quantity: 1,
      buyingPrice: 100,
      sellingPrice: 1000,
      totalBuyingPrice: 100,
      totalSellingPrice: 1000,
      profit: 900,
    );
    final loansBefore = app.loans.length;
    final sale = app.addSale(
      items: [item],
      totalAmount: 1000,
      totalBuyingPrice: 100,
      totalProfit: 900,
      paymentMethod: 'partial',
      amountPaid: 600,
      changeDue: 0,
      loanAmount: 400,
      customerName: 'Jane Doe',
      customerContact: '0700000000',
      loanPledgeDate: '2026-08-01',
    );
    expect(sale.hasLoan, true);
    expect(sale.loanAmount, 400);
    expect(sale.amountPaid, 600);
    expect(app.loans.length, loansBefore + 1);
    final loan = app.loans.first;
    expect(loan.customerName, 'Jane Doe');
    expect(loan.balance, 400);
    expect(loan.saleId, sale.id);
  });

  test('loan repayment settles the balance', () async {
    final app = await boot();
    final loan = app.addLoan(
      customerName: 'John',
      customerContact: '',
      amount: 500,
      pledgeDate: '2026-08-01',
    );
    app.recordLoanPayment(loan.id, 200);
    expect(app.loans.firstWhere((l) => l.id == loan.id).balance, 300);
    app.recordLoanPayment(loan.id, 999); // overpay clamps to balance
    final settled = app.loans.firstWhere((l) => l.id == loan.id);
    expect(settled.balance, 0);
    expect(settled.isSettled, true);
  });

  test('expense recording persists a cost', () async {
    final app = await boot();
    final before = app.expenses.length;
    app.addExpense(category: 'Rent', description: 'July rent', amount: 250000);
    expect(app.expenses.length, before + 1);
    expect(app.expenses.first.amount, 250000);
    expect(app.expenses.first.recordedByName, 'Alex Mercer');
  });
}
