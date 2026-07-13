import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/data/app_state.dart';

class SyncResult {
  final bool success;
  final int syncedCount;
  SyncResult(this.success, this.syncedCount);
}

/// Ports the original Express backend interactions. When no server URL is
/// configured (or it is unreachable) the app stays fully functional offline;
/// EOD analysis falls back to the same rule-based generator the server used.
class SyncService {
  final AppState app;
  SyncService(this.app);

  String get _base => app.serverUrl.trim().replaceAll(RegExp(r'/$'), '');
  bool get _hasServer => _base.isNotEmpty;

  String _fmt(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  /// Two-way sync: pushes unsynced sales + local state, pulls back the master.
  Future<SyncResult> triggerSync() async {
    if (app.offlineMode) {
      throw Exception('Cannot sync while in Offline Mode');
    }
    final unsynced = app.sales.where((s) => !s.synced).toList();

    if (!_hasServer) {
      // No backend configured: mark local sales as synced (single-device mode).
      for (final s in app.sales) {
        s.synced = true;
      }
      app.replaceSales(app.sales);
      return SyncResult(true, unsynced.length);
    }

    final payload = {
      'sales': unsynced.map((e) => e.toJson()).toList(),
      'products': app.products.map((e) => e.toJson()).toList(),
      'stockTransactions': app.transactions.map((e) => e.toJson()).toList(),
      'auditLogs': app.auditLogs.map((e) => e.toJson()).toList(),
      'reports': app.reports.map((e) => e.toJson()).toList(),
      'loans': app.loans.map((e) => e.toJson()).toList(),
      'expenses': app.expenses.map((e) => e.toJson()).toList(),
      // Staff is server-authoritative: never pushed, only pulled (see below and
      // the /api/staff endpoint). This stops a stale local cache from polluting
      // the cloud staff directory.
      'role': app.session.role.wire,
      'userId': app.session.userId,
      'hasLocalEdits': app.session.role == UserRole.manager,
    };

    final resp = await http
        .post(Uri.parse('$_base/api/sync'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Server returned status ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] == true) {
      if (data['sales'] != null) {
        app.replaceSales(((data['sales'] as List))
            .map((e) => Sale.fromJson(Map<String, dynamic>.from(e as Map))
              ..synced = true)
            .toList());
      }
      if (data['products'] != null) {
        app.replaceProducts(((data['products'] as List))
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['stockTransactions'] != null) {
        app.replaceTransactions(((data['stockTransactions'] as List))
            .map((e) =>
                StockTransaction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['auditLogs'] != null) {
        app.replaceAuditLogs(((data['auditLogs'] as List))
            .map((e) => AuditLog.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['reports'] != null) {
        app.replaceReports(((data['reports'] as List))
            .map((e) =>
                EndOfDayReport.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['loans'] != null) {
        app.replaceLoans(((data['loans'] as List))
            .map((e) => Loan.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['expenses'] != null) {
        app.replaceExpenses(((data['expenses'] as List))
            .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['staff'] != null) {
        app.replaceStaff(((data['staff'] as List))
            .map((e) =>
                StaffProfile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
    }
    return SyncResult(true, unsynced.length);
  }

  /// Pulls the authoritative staff directory from Neon so logins validate
  /// against the cloud, not a possibly-stale locally-cached PIN. Returns null
  /// (caller falls back to local staff) when offline or no server is set.
  Future<List<StaffProfile>?> fetchStaff() async {
    if (app.offlineMode || !_hasServer) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_base/api/staff'))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] == true && data['staff'] != null) {
        return ((data['staff'] as List))
            .map((e) => StaffProfile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      // offline / unreachable → caller uses local staff
    }
    return null;
  }

  /// Authoritatively upserts one staff member to Neon (managerial action).
  /// Best-effort: silently no-ops offline; the local change still stands.
  Future<void> saveStaffMember(StaffProfile p) async {
    if (app.offlineMode || !_hasServer) return;
    try {
      await http
          .post(Uri.parse('$_base/api/staff/save'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'staff': p.toJson(), 'role': app.session.role.wire}))
          .timeout(const Duration(seconds: 12));
    } catch (_) {}
  }

  /// Authoritatively removes one staff member from Neon (managerial action).
  Future<void> deleteStaffMember(String userId) async {
    if (app.offlineMode || !_hasServer) return;
    try {
      await http
          .post(Uri.parse('$_base/api/staff/delete'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'userId': userId, 'role': app.session.role.wire}))
          .timeout(const Duration(seconds: 12));
    } catch (_) {}
  }

  Future<bool> voidSale(String saleId) async {
    if (!_hasServer) {
      app.voidSaleLocal(saleId);
      return true;
    }
    final resp = await http
        .post(Uri.parse('$_base/api/sales/delete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'saleId': saleId,
              'role': app.session.role.wire,
              'userId': app.session.userId,
              'userName': app.session.name,
            }))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      final err = jsonDecode(resp.body) as Map<String, dynamic>;
      throw Exception(err['message'] ?? 'Server error voiding transaction');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['success'] == true) {
      if (data['sales'] != null) {
        app.replaceSales(((data['sales'] as List))
            .map((e) => Sale.fromJson(Map<String, dynamic>.from(e as Map))
              ..synced = true)
            .toList());
      }
      if (data['products'] != null) {
        app.replaceProducts(((data['products'] as List))
            .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['stockTransactions'] != null) {
        app.replaceTransactions(((data['stockTransactions'] as List))
            .map((e) =>
                StockTransaction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      if (data['auditLogs'] != null) {
        app.replaceAuditLogs(((data['auditLogs'] as List))
            .map((e) => AuditLog.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
    }
    return true;
  }

  /// End-of-day summary. Computed entirely on-device with a deterministic
  /// rule-based generator — no AI / external analysis service is involved.
  Future<Map<String, dynamic>> analyzeEod(
      List<Sale> todaySales, String date) async {
    return _ruleBasedReport(todaySales, date);
  }

  Map<String, dynamic> _ruleBasedReport(List<Sale> sales, String date) {
    final totalSales = sales.fold<num>(0, (a, s) => a + s.totalAmount);
    final totalProfit = sales.fold<num>(0, (a, s) => a + s.totalProfit);
    final totalStaked = sales.fold<num>(0, (a, s) => a + s.totalBuyingPrice);
    final count = sales.length;

    final lowStock =
        app.products.where((p) => p.currentStock <= p.minStockLevel).toList();
    final now = DateTime.now();
    final expiring = app.products.where((p) {
      if (p.expirationDate == null) return false;
      final exp = DateTime.tryParse(p.expirationDate!);
      if (exp == null) return false;
      final days = exp.difference(now).inDays;
      return days >= 0 && days <= 7;
    }).toList();

    const c = 'shs';
    return {
      'eodSummaryText':
          'Business operations on $date balanced successfully. The total revenue collected stood at $c ${_fmt(totalSales)}, with an inventory investment (staked capital) of $c ${_fmt(totalStaked)}. This yielded a net profitability of $c ${_fmt(totalProfit)}. A total of $count transactions were registered.',
      'ownerMessageDraft':
          '🌾 DAILY BUSINESS REPORT - $date\n------------------------\nTotal Sales: $c ${_fmt(totalSales)}\nTotal Staked: $c ${_fmt(totalStaked)}\nNet Profit: $c ${_fmt(totalProfit)}\nNo. of Sales: $count\n\n⚠️ Low Stock Alerts: ${lowStock.length} items.\n🗓️ Expiring Soon: ${expiring.length} items.\n\nBalanced and backed up securely.',
      'strategicAdvice': [
        'Inventory Capitalization: A total of $c ${_fmt(totalStaked)} was staked (buying cost). Ensure markup percentages remain aligned with market rates.',
        lowStock.isNotEmpty
            ? 'Low Stock Warnings: ${lowStock.take(3).map((p) => p.name).join(', ')} require replenishment.'
            : 'Low Stock Warnings: All core commodities have healthy stock levels.',
        'Waste Mitigation: Watch out for ${expiring.length} items near expiration to avoid financial losses due to spoilage.',
      ],
      'restockAlerts': lowStock
          .map((p) =>
              '${p.name} (SKU: ${p.sku}) - Current: ${p.currentStock} units left (Min threshold: ${p.minStockLevel})')
          .toList(),
    };
  }
}
