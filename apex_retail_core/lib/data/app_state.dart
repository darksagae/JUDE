import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/data/id.dart';
import 'package:apex_retail_core/data/seed_data.dart';
import 'package:apex_retail_core/data/sync_service.dart';

/// Central application store. Faithfully ports `localDB` (localStorage-backed)
/// to a [ChangeNotifier] backed by SharedPreferences, and adds the two-way
/// server sync from the original Express backend.
class AppState extends ChangeNotifier {
  static const _kProducts = 'sm_products';
  static const _kSales = 'sm_sales';
  static const _kTransactions = 'sm_transactions';
  static const _kAuditLogs = 'sm_audit_logs';
  static const _kReports = 'sm_reports';
  static const _kSession = 'sm_session';
  static const _kOfflineMode = 'sm_offline_mode';
  static const _kStaffProfiles = 'sm_staff_profiles';
  static const _kExpiredControl = 'sm_expired_control';
  static const _kCategories = 'sm_categories';
  static const _kExpenseCategories = 'sm_expense_categories';
  static const _kDirtyProducts = 'sm_dirty_products';
  static const _kDirtyLoans = 'sm_dirty_loans';
  static const _kPrinterSettings = 'sm_printer_settings';
  static const _kServerUrl = 'sm_server_url';
  static const _kLoans = 'sm_loans';
  static const _kExpenses = 'sm_expenses';
  static const _kSidebarCollapsed = 'sm_sidebar_collapsed';
  // Sequential account-ID allocation (IDs are issued in order and never reused).
  static const _kIdCounters = 'sm_id_counters';
  static const _kIssuedIds = 'sm_issued_ids';

  /// Default sync endpoint (the deployed Neon-backed backend on Vercel). Every
  /// device is wired to the shared database out of the box; sync runs silently
  /// in the background and there is no user-facing sync/DB configuration.
  static const defaultServerUrl =
      'https://apex-retail-ledger.vercel.app';

  late SharedPreferences _prefs;
  late SyncService _sync;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // In-memory state
  List<Product> products = [];
  List<Sale> sales = [];
  List<StockTransaction> transactions = [];
  List<AuditLog> auditLogs = [];
  List<EndOfDayReport> reports = [];
  List<StaffProfile> staff = [];
  List<String> categories = [];
  List<String> expenseCategories = [];

  /// Ids of products/loans this device has actually edited since its last
  /// successful sync. Sync pushes the whole catalog and loan book, but only these
  /// are offered to the server as authoritative — otherwise this device's stale
  /// copy of an untouched record would overwrite a restock or a repayment made on
  /// another terminal. Persisted so an offline edit survives a restart.
  Set<String> dirtyProductIds = {};
  Set<String> dirtyLoanIds = {};
  List<Loan> loans = [];
  List<Expense> expenses = [];
  late UserSession session;
  late PrinterSettings printerSettings;
  bool offlineMode = false;
  String expiredControl = 'restrict'; // 'restrict' | 'allow'
  String serverUrl = '';
  bool sidebarCollapsed = false; // worker can hide the nav for a bigger grid

  // Highest sequential number issued per account-ID prefix (W/M/TM), and the
  // full set of IDs ever issued. Together they guarantee new IDs are handed out
  // in order and an ID is never reused, even after the account is deleted.
  Map<String, int> _idCounters = {};
  Set<String> _issuedIds = {};

  // Session UI flags
  String lastSyncTime = 'Never';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _sync = SyncService(this);

    products = _readList(_kProducts, Product.fromJson, () => defaultProducts());
    products = products.map((p) => Product.fromJson(p.toJson())).toList();
    sales = _readList(_kSales, Sale.fromJson, () => seedSales());
    transactions = _readList(
        _kTransactions, StockTransaction.fromJson, () => seedStockTransactions());
    auditLogs = _readList(_kAuditLogs, AuditLog.fromJson, () => seedAuditLogs());
    reports = _readList(_kReports, EndOfDayReport.fromJson, () => []);
    staff = _readList(_kStaffProfiles, StaffProfile.fromJson, () => defaultStaff());
    categories = _readStringList(_kCategories, () => List.of(initialCategories));
    _migrateLegacyCategories();
    expenseCategories = _readStringList(
        _kExpenseCategories, () => List.of(initialExpenseCategories));
    dirtyProductIds = _readStringList(_kDirtyProducts, () => <String>[]).toSet();
    dirtyLoanIds = _readStringList(_kDirtyLoans, () => <String>[]).toSet();
    loans = _readList(_kLoans, Loan.fromJson, () => []);
    expenses = _readList(_kExpenses, Expense.fromJson, () => []);
    _purgeLegacyDemoData();

    final sessRaw = _prefs.getString(_kSession);
    session = sessRaw != null
        ? UserSession.fromJson(jsonDecode(sessRaw) as Map<String, dynamic>)
        : UserSession(userId: '', name: 'Not signed in', role: UserRole.worker);

    final printRaw = _prefs.getString(_kPrinterSettings);
    printerSettings = printRaw != null
        ? PrinterSettings.fromJson(jsonDecode(printRaw) as Map<String, dynamic>)
        : PrinterSettings(
            paperWidth: '80mm',
            ipAddress: '192.168.1.100',
            bluetoothAddress: '00:11:22:33:FF:EE',
            defaultFormat: 'receipt');

    offlineMode = _prefs.getBool(_kOfflineMode) ?? false;
    expiredControl = _prefs.getString(_kExpiredControl) ?? 'restrict';
    // First run defaults to the cloud backend; user can blank it for offline.
    serverUrl = _prefs.getString(_kServerUrl) ?? defaultServerUrl;
    // View preferences are stored per account so several people sharing one
    // device each keep their own settings.
    sidebarCollapsed = _prefs.getBool(_scoped(_kSidebarCollapsed)) ?? false;

    _loadIdState();
    _startConnectivityAutoSync();
  }

  /// Namespaces a preference key by the signed-in account so shared-device
  /// logins don't mix per-user settings/drafts. Business data (inventory,
  /// sales, loans, audit) stays shared and cloud-synced.
  String _scoped(String base) {
    final u = session.userId;
    return u.isEmpty ? base : '${base}__$u';
  }

  void _loadIdState() {
    final rawCounters = _prefs.getString(_kIdCounters);
    if (rawCounters != null) {
      _idCounters = (jsonDecode(rawCounters) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    final rawIssued = _prefs.getString(_kIssuedIds);
    if (rawIssued != null) {
      _issuedIds =
          (jsonDecode(rawIssued) as List).map((e) => e.toString()).toSet();
    }
    // Fold in any IDs the current directory already uses so the counters
    // continue in order and pre-existing IDs are treated as taken.
    for (final s in staff) {
      _absorbIssuedId(s.userId);
    }
    _persistIdState();
  }

  void _absorbIssuedId(String id) {
    if (id.isEmpty) return;
    _issuedIds.add(id);
    final m = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(id);
    if (m != null) {
      final prefix = m.group(1)!.toUpperCase();
      final n = int.tryParse(m.group(2)!) ?? 0;
      if (n > (_idCounters[prefix] ?? 0)) _idCounters[prefix] = n;
    }
  }

  void _persistIdState() {
    _prefs.setString(_kIdCounters, jsonEncode(_idCounters));
    _prefs.setString(_kIssuedIds, jsonEncode(_issuedIds.toList()));
  }

  /// Allocates the next account ID for [role] in sequence (W001, W002, …;
  /// M001…; TM001…). Skips any number already issued so an ID is never reused,
  /// even after the account it belonged to has been deleted.
  String nextStaffId(UserRole role) {
    final prefix = role == UserRole.manager
        ? 'M'
        : role == UserRole.topManager
            ? 'TM'
            : 'W';
    var n = _idCounters[prefix] ?? 0;
    String candidate;
    do {
      n++;
      candidate = '$prefix${n.toString().padLeft(3, '0')}';
    } while (
        _issuedIds.contains(candidate) || staff.any((s) => s.userId == candidate));
    _idCounters[prefix] = n;
    _issuedIds.add(candidate);
    _persistIdState();
    return candidate;
  }

  /// Records an externally-chosen ID as issued so it is never handed out again.
  void registerIssuedId(String id) {
    _absorbIssuedId(id);
    _persistIdState();
  }

  /// Watches the network and, the moment connectivity returns, pushes any
  /// offline-captured data (unsynced sales, restocks, edits) up to Neon and
  /// pulls the latest master back down. This is what makes "internet off →
  /// back on → auto-synced to the cloud database" work without user action.
  void _startConnectivityAutoSync() {
    // Guarded so a platform without the connectivity plugin (or a test
    // environment with no bindings) never blocks the app from starting.
    try {
      _connSub = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        final hasServer = serverUrl.trim().isNotEmpty;
        if (online && !offlineMode && hasServer) {
          triggerSync().catchError((_) => SyncResult(false, 0));
        }
      });
    } catch (_) {
      // Connectivity monitoring unavailable — sync still runs on sale/manual.
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  // ---- persistence helpers ----
  List<T> _readList<T>(String key, T Function(Map<String, dynamic>) fromJson,
      List<T> Function() seed) {
    final raw = _prefs.getString(key);
    if (raw == null) {
      final seeded = seed();
      _prefs.setString(
          key, jsonEncode(seeded.map((e) => (e as dynamic).toJson()).toList()));
      return seeded;
    }
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<String> _readStringList(String key, List<String> Function() seed) {
    final raw = _prefs.getString(key);
    if (raw == null) {
      final seeded = seed();
      _prefs.setString(key, jsonEncode(seeded));
      return seeded;
    }
    return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
  }

  void _save(String key, List list) =>
      _prefs.setString(key, jsonEncode(list.map((e) => e.toJson()).toList()));

  void _persistProducts() => _save(_kProducts, products);
  void _persistSales() => _save(_kSales, sales);
  void _persistTransactions() => _save(_kTransactions, transactions);
  void _persistAuditLogs() => _save(_kAuditLogs, auditLogs);
  void _persistReports() => _save(_kReports, reports);
  void _persistStaff() => _save(_kStaffProfiles, staff);
  void _persistCategories() => _prefs.setString(_kCategories, jsonEncode(categories));
  void _persistExpenseCategories() =>
      _prefs.setString(_kExpenseCategories, jsonEncode(expenseCategories));
  void _persistDirtyProducts() =>
      _prefs.setString(_kDirtyProducts, jsonEncode(dirtyProductIds.toList()));
  void _persistDirtyLoans() =>
      _prefs.setString(_kDirtyLoans, jsonEncode(dirtyLoanIds.toList()));

  /// Flags a product as locally edited so the next sync claims authority over it.
  void markProductDirty(String id) {
    if (id.isEmpty || !dirtyProductIds.add(id)) return;
    _persistDirtyProducts();
  }

  /// Flags a loan as locally edited so the next sync claims authority over it.
  void markLoanDirty(String id) {
    if (id.isEmpty || !dirtyLoanIds.add(id)) return;
    _persistDirtyLoans();
  }

  /// Called once the server has accepted these edits. Only the ids that were in
  /// the pushed payload are cleared, so anything edited while the request was in
  /// flight stays pending for the next sync.
  void clearDirtyAfterSync(List<String> products, List<String> loans) {
    if (products.isNotEmpty) {
      final done = products.toSet();
      dirtyProductIds.removeWhere((id) => done.contains(id));
      _persistDirtyProducts();
    }
    if (loans.isNotEmpty) {
      final done = loans.toSet();
      dirtyLoanIds.removeWhere((id) => done.contains(id));
      _persistDirtyLoans();
    }
  }

  /// Adopts the cloud's union of category names.
  void replaceCategories({List<String>? categories, List<String>? expenseCategories}) {
    var changed = false;
    if (categories != null && !_sameList(this.categories, categories)) {
      this.categories = List.of(categories);
      _persistCategories();
      changed = true;
    }
    if (expenseCategories != null &&
        !_sameList(this.expenseCategories, expenseCategories)) {
      this.expenseCategories = List.of(expenseCategories);
      _persistExpenseCategories();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  void _persistLoans() => _save(_kLoans, loans);
  void _persistExpenses() => _save(_kExpenses, expenses);

  // ---- getters ----
  int get pendingSyncCount => sales.where((s) => !s.synced).length;
  bool get isManager => session.role.isManagerial;

  // ---- audit ----
  void logAction(String userId, String userName, UserRole role,
      String actionType, String details) {
    auditLogs.insert(
        0,
        AuditLog(
          id: genId(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          userId: userId,
          userName: userName,
          userRole: role,
          actionType: actionType,
          details: details,
        ));
    if (auditLogs.length > 1000) auditLogs = auditLogs.sublist(0, 1000);
    _persistAuditLogs();
  }

  void _log(String actionType, String details) =>
      logAction(session.userId, session.name, session.role, actionType, details);

  String _productChangeDetails(Product before, Product after) {
    final changes = <String>[];
    void cmp(String label, Object a, Object b) {
      if ('$a' != '$b') changes.add('$label: $a → $b');
    }

    void cmpMoney(String label, num a, num b) {
      if (a != b) changes.add('$label: ${shs(a)} → ${shs(b)}');
    }

    cmp('name', before.name, after.name);
    cmp('SKU', before.sku, after.sku);
    cmp('category', before.category, after.category);
    cmpMoney('buying cost', before.buyingPrice, after.buyingPrice);
    cmpMoney('wholesale price', before.wholesalePrice, after.wholesalePrice);
    cmpMoney('retail price', before.retailPrice, after.retailPrice);
    cmp('stock', before.currentStock, after.currentStock);
    cmp('low threshold', before.minStockLevel, after.minStockLevel);
    cmp('sale type', before.saleType, after.saleType);
    cmp('starred', before.isFavorite ? 'yes' : 'no', after.isFavorite ? 'yes' : 'no');
    cmp('expiry', before.expirationDate ?? 'none', after.expirationDate ?? 'none');
    return changes.join('; ');
  }

  /// Adds [raw] to the category list when new, then returns the trimmed name.
  String ensureCategory(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return categories.isNotEmpty ? categories.first : 'Seeds';
    if (!categories.contains(n)) addCategory(n);
    return n;
  }

  // ---- session ----
  // The real, authenticated account a switch-into-another-account started
  // from — null when not currently switched away from it. Lets a manager or
  // top manager return to their own login without a full logout.
  UserSession? homeSession;

  void setSession(UserSession s, {bool logLogin = true}) {
    if (logLogin) {
      // A genuine login — this account is now "home", not a switched-into one.
      homeSession = null;
    } else {
      // First switch away from the real account: remember it so we can
      // return to it later, no matter how many more switches happen after.
      homeSession ??= session;
    }
    session = s;
    _prefs.setString(_kSession, jsonEncode(s.toJson()));
    // Load this account's own view preferences (kept separate per account so a
    // shared device doesn't mix them between users).
    sidebarCollapsed = _prefs.getBool(_scoped(_kSidebarCollapsed)) ?? false;
    if (logLogin) {
      logAction(s.userId, s.name, s.role, 'LOGIN',
          '${s.role.label} session initialized: ${s.name}');
    }
    notifyListeners();
  }

  /// Returns to the real account a switch started from, without a full
  /// logout. No-op if not currently switched into another account.
  void switchBack() {
    final home = homeSession;
    if (home == null) return;
    // Attributed to the home account (not the impersonated one) so this
    // entry is hidden from lower roles exactly like the account it belongs
    // to would be — switching back from a Manager shouldn't leak the Top
    // Manager's name into a log a Manager can read.
    logAction(home.userId, home.name, home.role, 'SWITCH_BACK',
        'Returned to own account after using "${session.name}" (${session.role.label})');
    homeSession = null;
    session = home;
    _prefs.setString(_kSession, jsonEncode(home.toJson()));
    sidebarCollapsed = _prefs.getBool(_scoped(_kSidebarCollapsed)) ?? false;
    notifyListeners();
  }

  /// Fully signs out — clears the active session AND any impersonation
  /// state. Locking the terminal after switching into another account must
  /// not leave a stale [homeSession] behind for the next login to inherit.
  void logout() {
    logAction(session.userId, session.name, session.role, 'LOGOUT',
        'Terminal locked/secured');
    homeSession = null;
    session = UserSession(userId: '', name: 'Not signed in', role: UserRole.worker);
    _prefs.remove(_kSession);
    notifyListeners();
  }

  void setOfflineMode(bool v) {
    offlineMode = v;
    _prefs.setBool(_kOfflineMode, v);
    _log('SYNC', 'Offline mode toggled to $v');
    notifyListeners();
  }

  void setServerUrl(String url) {
    serverUrl = url.trim();
    _prefs.setString(_kServerUrl, serverUrl);
    notifyListeners();
  }

  void setSidebarCollapsed(bool v) {
    sidebarCollapsed = v;
    _prefs.setBool(_scoped(_kSidebarCollapsed), v);
    notifyListeners();
  }

  void toggleSidebar() => setSidebarCollapsed(!sidebarCollapsed);

  // ---- categories ----

  /// Sends a category add/delete to its own authoritative endpoint and adopts the
  /// server's lists. Fire-and-forget: offline, the local change stands and unions
  /// in on the next successful sync.
  Future<void> _pushCategoryChange(String action, String kind, String name) async {
    if (offlineMode || serverUrl.trim().isEmpty) return;
    final res = await _sync.pushCategoryChange(action, kind, name);
    if (res == null) return;
    replaceCategories(
      categories: res.categories.isNotEmpty ? res.categories : null,
      expenseCategories:
          res.expenseCategories.isNotEmpty ? res.expenseCategories : null,
    );
  }

  bool addCategory(String category) {
    final n = category.trim();
    if (n.isNotEmpty && !categories.contains(n)) {
      categories.add(n);
      _persistCategories();
      _log('CATEGORY_CREATE', '${session.name} created category: $n');
      _pushCategoryChange('add', 'product', n);
      notifyListeners();
      return true;
    }
    return false;
  }

  bool editCategory(String oldName, String newName) {
    final idx = categories.indexOf(oldName);
    final n = newName.trim();
    if (idx != -1 && n.isNotEmpty && !categories.contains(n)) {
      categories[idx] = n;
      var updated = 0;
      for (final p in products) {
        if (p.category == oldName) {
          p.category = n;
          updated++;
        }
      }
      _persistCategories();
      if (updated > 0) {
        _persistProducts();
        for (final p in products) {
          if (p.category == n) markProductDirty(p.id);
        }
      }
      _log('CATEGORY_UPDATE',
          'Edited category $oldName -> $n. Re-assigned $updated products.');
      // A rename is an add of the new name plus a delete of the old one.
      _pushCategoryChange('add', 'product', n);
      _pushCategoryChange('delete', 'product', oldName);
      notifyListeners();
      return true;
    }
    return false;
  }

  bool deleteCategory(String category, {String? fallback}) {
    final fb = fallback ?? (categories.isNotEmpty ? categories.first : 'Seeds');
    final idx = categories.indexOf(category);
    if (idx != -1) {
      categories.removeAt(idx);
      if (!categories.contains(fb)) categories.add(fb);
      var updated = 0;
      for (final p in products) {
        if (p.category == category) {
          p.category = fb;
          updated++;
        }
      }
      _persistCategories();
      if (updated > 0) {
        _persistProducts();
        for (final p in products) {
          if (p.category == fb) markProductDirty(p.id);
        }
      }
      _log('CATEGORY_DELETE',
          'Deleted category $category. Re-assigned $updated products to $fb.');
      _pushCategoryChange('delete', 'product', category);
      notifyListeners();
      return true;
    }
    return false;
  }

  // ---- expense categories ----
  bool addExpenseCategory(String category) {
    final n = category.trim();
    if (n.isNotEmpty && !expenseCategories.contains(n)) {
      expenseCategories.add(n);
      _persistExpenseCategories();
      _log('EXPENSE_CATEGORY_CREATE', '${session.name} created expense category: $n');
      _pushCategoryChange('add', 'expense', n);
      notifyListeners();
      return true;
    }
    return false;
  }

  bool editExpenseCategory(String oldName, String newName) {
    final idx = expenseCategories.indexOf(oldName);
    final n = newName.trim();
    if (idx != -1 && n.isNotEmpty && !expenseCategories.contains(n)) {
      expenseCategories[idx] = n;
      var updated = 0;
      for (final e in expenses) {
        if (e.category == oldName) {
          e.category = n;
          updated++;
        }
      }
      _persistExpenseCategories();
      if (updated > 0) _persistExpenses();
      _log('EXPENSE_CATEGORY_UPDATE',
          'Edited expense category $oldName -> $n. Re-assigned $updated expenses.');
      // A rename is an add of the new name plus a delete of the old one.
      _pushCategoryChange('add', 'expense', n);
      _pushCategoryChange('delete', 'expense', oldName);
      notifyListeners();
      return true;
    }
    return false;
  }

  bool deleteExpenseCategory(String category, {String? fallback}) {
    final fb = fallback ??
        (expenseCategories.isNotEmpty ? expenseCategories.first : 'Miscellaneous');
    final idx = expenseCategories.indexOf(category);
    if (idx != -1) {
      expenseCategories.removeAt(idx);
      if (!expenseCategories.contains(fb)) expenseCategories.add(fb);
      var updated = 0;
      for (final e in expenses) {
        if (e.category == category) {
          e.category = fb;
          updated++;
        }
      }
      _persistExpenseCategories();
      if (updated > 0) _persistExpenses();
      _log('EXPENSE_CATEGORY_DELETE',
          'Deleted expense category $category. Re-assigned $updated expenses to $fb.');
      _pushCategoryChange('delete', 'expense', category);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// One-time purge of legacy demo/seed data that older installs cached in
  /// local storage before the demo data was removed. Runs once (guarded by a
  /// data-version flag). Targeted to the demo signature so any real data the
  /// user has already entered is preserved: demo products use ids P001–P010
  /// (real ones are P100+), the test artifact used sku REAL-1, and demo audit
  /// logs / staff came from the removed M001 / W001 / W002 accounts.
  static const _kDataVersion = 'sm_data_version';
  static const _dataVersion = 2;
  void _purgeLegacyDemoData() {
    final ver = _prefs.getInt(_kDataVersion) ?? 1;
    if (ver >= _dataVersion) return;

    bool isDemoId(String id) => RegExp(r'^P0\d\d$').hasMatch(id);
    const demoUsers = {'M001', 'W001', 'W002'};

    products =
        products.where((p) => !isDemoId(p.id) && p.sku != 'REAL-1').toList();
    transactions =
        transactions.where((t) => !isDemoId(t.productId)).toList();
    sales = sales
        .where((s) => !s.items.any((it) => isDemoId(it.productId)))
        .toList();
    auditLogs =
        auditLogs.where((l) => !demoUsers.contains(l.userId)).toList();
    staff = staff.where((s) => !demoUsers.contains(s.userId)).toList();
    if (staff.isEmpty) staff = defaultStaff();

    _persistProducts();
    _persistTransactions();
    _persistSales();
    _persistAuditLogs();
    _persistStaff();
    _prefs.setInt(_kDataVersion, _dataVersion);
  }

  /// One-time upgrade from the original retail demo categories to agri defaults.
  void _migrateLegacyCategories() {
    final isLegacy = categories.length == legacyRetailCategories.length &&
        legacyRetailCategories.every(categories.contains);
    if (!isLegacy) return;

    categories = List.of(initialCategories);
    _persistCategories();

    var updated = 0;
    for (final p in products) {
      final mapped = legacyCategoryMigration[p.category];
      if (mapped != null) {
        p.category = mapped;
        updated++;
      }
    }
    if (updated > 0) _persistProducts();
  }

  // ---- printer / expired control ----
  void setPrinterSettings(PrinterSettings s) {
    printerSettings = s;
    _prefs.setString(_kPrinterSettings, jsonEncode(s.toJson()));
    notifyListeners();
  }

  void setExpiredSalesControl(String control) {
    expiredControl = control;
    _prefs.setString(_kExpiredControl, control);
    _log('EXPIRED_CONTROL_SET',
        'System configuration updated: sales of expired commodities set to ${control.toUpperCase()}');
    notifyListeners();
  }

  // ---- staff ----
  // True while an authoritative staff create/edit/delete is being pushed to
  // Neon. While set, a concurrent bulk sync must NOT overwrite the local staff
  // directory (see replaceStaff): the server's staff snapshot may still be
  // pre-change, and clobbering with it is what made new accounts vanish and
  // deleted accounts reappear.
  bool _staffWriteInFlight = false;

  void setStaff(List<StaffProfile> s) {
    final old = List<StaffProfile>.from(staff);
    staff = s;
    for (final n in s) {
      _absorbIssuedId(n.userId);
    }
    _persistIdState();
    _persistStaff();
    notifyListeners();
    // Propagate the change to the authoritative Neon staff directory (staff is
    // never carried by the bulk sync) and adopt the server's response so local
    // exactly matches the database. Best-effort; local change stands offline.
    _syncStaffDiff(old, s);
  }

  Future<void> _syncStaffDiff(
      List<StaffProfile> before, List<StaffProfile> after) async {
    // Offline (or no backend): keep the optimistic local change; it will be
    // reconciled the next time this device is online and manages staff.
    if (offlineMode || serverUrl.trim().isEmpty) return;

    _staffWriteInFlight = true;
    try {
      final afterIds = after.map((e) => e.userId).toSet();
      List<StaffProfile>? authoritative;

      // Deletes first, then upserts, awaiting each so the database is the
      // source of truth before we adopt its answer.
      for (final o in before) {
        if (!afterIds.contains(o.userId)) {
          authoritative = await _sync.deleteStaffMember(o.userId) ?? authoritative;
        }
      }
      for (final n in after) {
        final prev = before
            .where((e) => e.userId == n.userId)
            .cast<StaffProfile?>()
            .firstOrNull;
        if (prev == null ||
            jsonEncode(prev.toJson()) != jsonEncode(n.toJson())) {
          authoritative = await _sync.saveStaffMember(n) ?? authoritative;
        }
      }

      // Adopt the server's authoritative directory so a create is confirmed in
      // the database and a delete truly sticks (no stale bulk-sync pull can
      // resurrect it). Only when the server actually answered.
      if (authoritative != null && authoritative.isNotEmpty) {
        staff = authoritative;
        for (final n in authoritative) {
          _absorbIssuedId(n.userId);
        }
        _persistIdState();
        _persistStaff();
        notifyListeners();
      }
    } finally {
      _staffWriteInFlight = false;
    }
  }

  // ---- SKU helper ----
  String _autoSku(String category, String name) {
    final catCode = category.isNotEmpty
        ? category
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0])
            .join()
            .toUpperCase()
            .substring(0, category.split(' ').length.clamp(1, 3))
        : 'GEN';
    final cleanName = name.isNotEmpty
        ? name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase()
        : 'PRD';
    final nm = cleanName.isEmpty
        ? 'PRD'
        : cleanName.substring(0, cleanName.length.clamp(0, 3));
    return '$catCode-$nm-${randInt(100000, 999999)}';
  }

  String autoSku(String category, String name) => _autoSku(category, name);

  // ---- products ----
  Product addProduct({
    required String name,
    required String sku,
    required String category,
    required num buyingPrice,
    num? sellingPrice,
    num? wholesalePrice,
    num? retailPrice,
    String unitLabel = 'piece',
    required num currentStock,
    required num minStockLevel,
    String saleType = 'retail',
    required String? expirationDate,
  }) {
    var finalSku = sku.trim();
    if (finalSku.isEmpty) finalSku = _autoSku(category, name);
    final wholesale = wholesalePrice ?? buyingPrice;
    final retail = retailPrice ?? wholesale;
    final sell = sellingPrice ?? retail;
    final p = Product(
      id: genProductId(),
      name: name,
      sku: finalSku,
      category: category,
      buyingPrice: buyingPrice,
      sellingPrice: sell < retail ? retail : sell,
      wholesalePrice: wholesale,
      retailPrice: retail,
      unitLabel: unitLabel,
      currentStock: currentStock,
      minStockLevel: minStockLevel,
      saleType: saleType,
      expirationDate: expirationDate,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    products.add(p);
    _persistProducts();
    markProductDirty(p.id);
    _log(
        'PRODUCT_CREATE',
        '${session.role.label} ${session.name} registered "${p.name}" (${p.sku}): '
        'category ${p.category}; buying ${shs(p.buyingPrice)}; '
        'wholesale ${shs(p.wholesalePrice)}; retail ${shs(p.retailPrice)}; '
        'stock ${p.currentStock} ${p.unitLabel}; low alert at ${p.minStockLevel}');
    _addTransaction(
      productId: p.id,
      productName: p.name,
      quantity: p.currentStock,
      type: 'in',
      buyingPriceAtTransaction: p.buyingPrice,
      reason: 'initial',
      notes: 'Initial stock setup',
    );
    // Push immediately so the new commodity and its price appear on every
    // other account/device without waiting for the next periodic sync tick
    // (and isn't clobbered by a pull that lands first — whole-array replace,
    // no merge, on the products collection).
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
    return p;
  }

  void updateProduct(Product updated) {
    final idx = products.indexWhere((p) => p.id == updated.id);
    if (idx == -1) return;
    var finalSku = updated.sku.trim();
    if (finalSku.isEmpty) finalSku = _autoSku(updated.category, updated.name);
    updated.sku = finalSku;
    // Enforce the price floor: selling price can move freely but not below
    // the per-unit retail price.
    if (updated.retailPrice > 0 && updated.sellingPrice < updated.retailPrice) {
      updated.sellingPrice = updated.retailPrice;
    }
    final original = products[idx];
    final diff = updated.currentStock - original.currentStock;
    products[idx] = updated;
    _persistProducts();
    markProductDirty(updated.id);
    if (diff != 0) {
      _addTransaction(
        productId: updated.id,
        productName: updated.name,
        quantity: diff,
        type: diff > 0 ? 'in' : 'out',
        buyingPriceAtTransaction: updated.buyingPrice,
        reason: diff > 0 ? 'restock' : 'audit_adjustment',
        notes: 'Stock adjustment from inventory management',
      );
    }
    final changes = _productChangeDetails(original, updated);
    if (changes.isNotEmpty) {
      _log(
          'PRODUCT_UPDATE',
          '${session.role.label} ${session.name} edited "${updated.name}" '
          '(${updated.sku}): $changes');
    }
    // Push immediately — a price/stock edit must reach every other
    // account/device right away, not sit until the next periodic tick.
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
  }

  /// Permanently removes a product from the catalog. Super Admin only.
  bool deleteProduct(String productId) {
    if (session.role != UserRole.topManager) return false;
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx == -1) return false;
    final p = products.removeAt(idx);
    _persistProducts();
    _log(
        'PRODUCT_DELETE',
        'Super Admin ${session.name} deleted "${p.name}" (${p.sku}) '
        'from inventory. Last stock: ${p.currentStock}; category: ${p.category}.');
    // A plain triggerSync would only re-push the (upsert-only) catalog and the
    // server would keep — then return — the deleted row, resurrecting it. Route
    // through the authoritative delete endpoint and adopt the server's answer.
    _deleteProductRemote(productId);
    notifyListeners();
    return true;
  }

  // True while an authoritative product delete is being pushed to Neon; blocks a
  // concurrent bulk sync from re-adding the just-deleted product (see
  // replaceProducts).
  bool _productWriteInFlight = false;

  Future<void> _deleteProductRemote(String productId) async {
    if (offlineMode || serverUrl.trim().isEmpty) return;
    _productWriteInFlight = true;
    try {
      final authoritative = await _sync.deleteProduct(productId);
      if (authoritative != null) {
        products = authoritative.map((x) => Product.fromJson(x.toJson())).toList();
        _persistProducts();
        notifyListeners();
      }
    } finally {
      _productWriteInFlight = false;
    }
  }

  void toggleProductFavorite(String productId) {
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;
    final p = products[idx];
    p.isFavorite = !p.isFavorite;
    _persistProducts();
    markProductDirty(p.id);
    _log(
        'PRODUCT_UPDATE',
        '${session.name} ${p.isFavorite ? 'starred' : 'unstarred'} '
        '"${p.name}" (${p.sku}) for quick POS access');
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
  }

  /// Returns a map: {type: 'new_batch'|'merged', product: Product}
  Map<String, dynamic>? restockProduct(
    String productId,
    num qty, {
    num? buyingPrice,
    String? newExpirationDate,
    bool createNewBatch = false,
  }) {
    final p = products.firstWhere((prod) => prod.id == productId,
        orElse: () => throw StateError('not found'));

    if (createNewBatch &&
        newExpirationDate != null &&
        newExpirationDate.isNotEmpty &&
        p.expirationDate != newExpirationDate) {
      final cleanSku = p.sku.split('-B')[0];
      final otherBatches =
          products.where((prod) => prod.sku.startsWith(cleanSku)).length;
      final newSku = '$cleanSku-B${otherBatches + 1}';
      final newName = '${p.name} (Batch ${otherBatches + 1})';
      final np = Product(
        id: genProductId(),
        name: newName,
        sku: newSku,
        category: p.category,
        buyingPrice: buyingPrice ?? p.buyingPrice,
        sellingPrice: p.sellingPrice,
        wholesalePrice: p.wholesalePrice,
        retailPrice: p.retailPrice,
        unitLabel: p.unitLabel,
        currentStock: qty,
        minStockLevel: p.minStockLevel,
        saleType: p.saleType,
        expirationDate: newExpirationDate,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      products.add(np);
      _persistProducts();
      _log('PRODUCT_CREATE',
          'Created separate batch for: ${np.name} with different expiry: $newExpirationDate');
      _addTransaction(
        productId: np.id,
        productName: np.name,
        quantity: qty,
        type: 'in',
        buyingPriceAtTransaction: np.buyingPrice,
        reason: 'restock',
        notes: 'Batch restock with different expiry $newExpirationDate',
      );
      markProductDirty(np.id);
      if (!offlineMode) {
        triggerSync().catchError((_) => SyncResult(false, 0));
      }
      notifyListeners();
      return {'type': 'new_batch', 'product': np};
    }

    final originalStock = p.currentStock;
    final originalBuying = p.buyingPrice;
    final originalExpiry = p.expirationDate;
    p.currentStock += qty;
    if (buyingPrice != null) p.buyingPrice = buyingPrice;
    if (newExpirationDate != null) {
      p.expirationDate = newExpirationDate.isEmpty ? null : newExpirationDate;
    }
    _persistProducts();
    final parts = <String>['added $qty units'];
    if (buyingPrice != null && buyingPrice != originalBuying) {
      parts.add('buying cost ${shs(originalBuying)} → ${shs(buyingPrice)}');
    }
    if (newExpirationDate != null &&
        (newExpirationDate.isEmpty ? null : newExpirationDate) !=
            originalExpiry) {
      parts.add(
          'expiry ${originalExpiry ?? 'none'} → ${p.expirationDate ?? 'none'}');
    }
    _log(
        'STOCK_IN',
        '${session.role.label} ${session.name} restocked "${p.name}" (${p.sku}): '
        '${parts.join('; ')}. Stock $originalStock → ${p.currentStock}');
    _addTransaction(
      productId: p.id,
      productName: p.name,
      quantity: qty,
      type: 'in',
      buyingPriceAtTransaction: buyingPrice ?? p.buyingPrice,
      reason: 'restock',
      notes: 'Manual stock-in replenishment',
    );
    markProductDirty(p.id);
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
    return {'type': 'merged', 'product': p};
  }

  // ---- transactions ----
  void _addTransaction({
    required String productId,
    required String productName,
    required num quantity,
    required String type,
    required num buyingPriceAtTransaction,
    required String reason,
    String? notes,
  }) {
    transactions.add(StockTransaction(
      id: genId(),
      productId: productId,
      productName: productName,
      quantity: quantity,
      type: type,
      buyingPriceAtTransaction: buyingPriceAtTransaction,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      operatorId: session.userId,
      operatorName: session.name,
      reason: reason,
      notes: notes,
    ));
    _persistTransactions();
  }

  // ---- sales ----
  Sale addSale({
    required List<SaleItem> items,
    required num totalAmount,
    required num totalBuyingPrice,
    required num totalProfit,
    required String paymentMethod,
    required num amountPaid,
    required num changeDue,
    num loanAmount = 0,
    String? customerName,
    String? customerContact,
    String? loanPledgeDate,
    String? mobileMoneyTxId,
  }) {
    final now = DateTime.now();
    final datePart = now.toUtc().toIso8601String().substring(0, 10).replaceAll('-', '');
    final resolvedPledgeDate = loanAmount > 0
        ? (loanPledgeDate ??
            DateTime.now()
                .add(const Duration(days: 7))
                .toIso8601String()
                .substring(0, 10))
        : null;
    final sale = Sale(
      id: 'TX-$datePart-${randInt(100, 999)}',
      items: items,
      totalAmount: totalAmount,
      totalBuyingPrice: totalBuyingPrice,
      totalProfit: totalProfit,
      paymentMethod: loanAmount > 0 ? 'partial' : paymentMethod,
      amountPaid: amountPaid,
      changeDue: changeDue,
      loanAmount: loanAmount,
      customerName: customerName,
      customerContact: loanAmount > 0 ? customerContact : null,
      loanPledgeDate: resolvedPledgeDate,
      timestamp: now.toUtc().toIso8601String(),
      cashierId: session.userId,
      cashierName: session.name,
      synced: false,
      mobileMoneyTxId: mobileMoneyTxId,
    );

    for (final item in sale.items) {
      final idx = products.indexWhere((prod) => prod.id == item.productId);
      if (idx != -1) {
        final p = products[idx];
        p.currentStock = (p.currentStock - item.quantity).clamp(0, double.infinity);
        _addTransaction(
          productId: p.id,
          productName: p.name,
          quantity: -item.quantity,
          type: 'out',
          buyingPriceAtTransaction: item.buyingPrice,
          reason: 'sale',
          notes: 'POS Transaction ${sale.id}',
        );
      }
    }
    _persistProducts();
    sales.add(sale);
    _persistSales();
    _log('SALE',
        'Completed POS sale ${sale.id}. Total: shs ${_fmt(sale.totalAmount)}'
        '${loanAmount > 0 ? ' (Cash: shs ${_fmt(amountPaid)}, Loan: shs ${_fmt(loanAmount)})' : ''}');

    // If part of the sale is unpaid, register it as a loan against the customer.
    // Carry the sale's profit margin so that, under cash-basis accounting, the
    // credit portion's profit is recognized as the loan is repaid (not now).
    if (loanAmount > 0) {
      addLoan(
        customerName: customerName ?? 'Walk-in Customer',
        customerContact: customerContact ?? '',
        amount: loanAmount,
        pledgeDate: resolvedPledgeDate!,
        saleId: sale.id,
        notes: 'Balance from POS sale ${sale.id}',
        profitRate: totalAmount > 0 ? totalProfit / totalAmount : 0,
        silent: true,
      );
    }

    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
    return sale;
  }

  // ---- loans ----
  Loan addLoan({
    required String customerName,
    required String customerContact,
    required num amount,
    required String pledgeDate,
    String? saleId,
    String? notes,
    num profitRate = 0,
    bool silent = false,
  }) {
    final loan = Loan(
      id: 'LN-${randInt(10000, 99999)}',
      customerName: customerName,
      customerContact: customerContact,
      originalAmount: amount,
      amountPaid: 0,
      pledgeDate: pledgeDate,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      createdById: session.userId,
      createdByName: session.name,
      saleId: saleId,
      notes: notes,
      profitRate: profitRate,
    );
    loans.insert(0, loan);
    _persistLoans();
    markLoanDirty(loan.id);
    _log('LOAN_CREATE',
        'Registered loan of shs ${_fmt(amount)} for $customerName (due $pledgeDate)');
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    if (!silent) notifyListeners();
    return loan;
  }

  void recordLoanPayment(String loanId, num amount) {
    final loan = loans.where((l) => l.id == loanId).cast<Loan?>().firstOrNull;
    if (loan == null || amount <= 0) return;
    final applied = amount > loan.balance ? loan.balance : amount;
    loan.amountPaid += applied;
    loan.payments.insert(
        0,
        LoanPayment(
          id: genId(),
          amount: applied,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          receivedById: session.userId,
          receivedByName: session.name,
        ));
    // Stamp the settlement time the moment the balance first hits zero, so the
    // settled state is explicit in the database for any connected system.
    final justSettled = loan.isSettled && loan.settledAt == null;
    if (justSettled) {
      loan.settledAt = DateTime.now().toUtc().toIso8601String();
    }
    _persistLoans();
    markLoanDirty(loan.id);
    _log('LOAN_PAYMENT',
        'Received shs ${_fmt(applied)} on loan ${loan.id} (${loan.customerName}). Balance: shs ${_fmt(loan.balance)}');
    if (justSettled) {
      _log('LOAN_SETTLED',
          'Loan ${loan.id} (${loan.customerName}) fully settled — total ${_fmt(loan.originalAmount)} paid off.');
    }
    // Push immediately, same as addSale: without this, a periodic pull-sync
    // landing before the next scheduled push can overwrite this device's
    // local `loans` list (whole-array replace, no merge) and silently lose
    // the payment that was just recorded.
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
  }

  /// Adds extra credit to an existing loan — e.g. the customer takes more
  /// commodities against the same running tab instead of a fresh loan.
  void increaseLoan(String loanId, num amount, {String? notes}) {
    final loan = loans.where((l) => l.id == loanId).cast<Loan?>().firstOrNull;
    if (loan == null || amount <= 0) return;
    loan.originalAmount += amount;
    if (notes != null && notes.trim().isNotEmpty) {
      loan.notes = [if (loan.notes != null) loan.notes!, notes.trim()].join('; ');
    }
    // Adding credit can re-open a previously settled loan; drop the stale
    // settlement stamp so the stored status reflects reality.
    if (!loan.isSettled) loan.settledAt = null;
    _persistLoans();
    markLoanDirty(loan.id);
    _log('LOAN_INCREASE',
        'Added shs ${_fmt(amount)} more credit to loan ${loan.id} (${loan.customerName}). New balance: shs ${_fmt(loan.balance)}');
    if (!offlineMode) {
      triggerSync().catchError((_) => SyncResult(false, 0));
    }
    notifyListeners();
  }

  bool _loanWriteInFlight = false;

  void deleteLoan(String loanId) {
    loans.removeWhere((l) => l.id == loanId);
    _persistLoans();
    _log('LOAN_DELETE', 'Deleted loan record $loanId');
    // Route through the authoritative delete endpoint: a plain sync would only
    // merge the (upsert-only) loan list and the server would return the deleted
    // loan straight back, resurrecting it.
    _deleteLoanRemote(loanId);
    notifyListeners();
  }

  Future<void> _deleteLoanRemote(String loanId) async {
    if (offlineMode || serverUrl.trim().isEmpty) return;
    _loanWriteInFlight = true;
    try {
      final authoritative = await _sync.deleteLoan(loanId);
      if (authoritative != null) {
        loans = authoritative;
        _persistLoans();
        notifyListeners();
      }
    } finally {
      _loanWriteInFlight = false;
    }
  }

  // ---- cash-basis financials ----
  /// Profit recognized on a sale under cash-basis accounting: proportional to
  /// the cash actually collected at checkout. The profit on any credit (loan)
  /// portion is deferred and recognized later, as the loan is repaid (see
  /// [loanCollections]). For a full-cash sale this equals the whole profit.
  num recognizedSaleProfit(Sale s) =>
      s.totalAmount > 0 ? s.totalProfit * (s.amountPaid / s.totalAmount) : s.totalProfit;

  /// Cash collected and profit recognized from loan repayments whose payment
  /// date satisfies [inRange] (local time). Profit is realized when the money
  /// is received, so it lands on the payment's own date — not the sale's.
  ({num cash, num profit}) loanCollections(bool Function(DateTime local) inRange) {
    num cash = 0;
    num profit = 0;
    for (final l in loans) {
      for (final p in l.payments) {
        final dt = DateTime.tryParse(p.timestamp)?.toLocal();
        if (dt == null || !inRange(dt)) continue;
        cash += p.amount;
        profit += p.amount * (l.profitRate ?? 0);
      }
    }
    return (cash: cash, profit: profit);
  }

  List<Loan> get activeLoans => loans.where((l) => !l.isSettled).toList();
  List<Loan> get overdueLoans =>
      loans.where((l) => l.isOverdue()).toList();
  List<Loan> get dueSoonLoans => loans
      .where((l) => !l.isSettled && !l.isOverdue() && l.daysUntilDue() <= 3)
      .toList();
  num get totalOutstandingLoans =>
      loans.fold<num>(0, (a, l) => a + l.balance);

  // ---- expenses ----
  Expense addExpense({
    required String category,
    required String description,
    required num amount,
  }) {
    final e = Expense(
      id: 'EXP-${randInt(10000, 99999)}',
      category: category,
      description: description,
      amount: amount,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      recordedById: session.userId,
      recordedByName: session.name,
    );
    expenses.insert(0, e);
    _persistExpenses();
    _log('EXPENSE_RECORD',
        'Recorded $category expense of shs ${_fmt(amount)}: $description');
    notifyListeners();
    return e;
  }

  bool _expenseWriteInFlight = false;

  void deleteExpense(String id) {
    expenses.removeWhere((e) => e.id == id);
    _persistExpenses();
    _log('EXPENSE_DELETE', 'Deleted expense $id');
    // Authoritative delete: without it the next sync's expense list (which the
    // server only ever appends to) resurrects the deleted expense.
    _deleteExpenseRemote(id);
    notifyListeners();
  }

  Future<void> _deleteExpenseRemote(String id) async {
    if (offlineMode || serverUrl.trim().isEmpty) return;
    _expenseWriteInFlight = true;
    try {
      final authoritative = await _sync.deleteExpense(id);
      if (authoritative != null) {
        expenses = authoritative;
        _persistExpenses();
        notifyListeners();
      }
    } finally {
      _expenseWriteInFlight = false;
    }
  }

  String _fmt(num n) => n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  // ---- staff profile lookup ----
  bool supervisorPasscodeMatches(String pass) => staff.any((s) =>
      (s.role == UserRole.manager || s.role == UserRole.topManager) &&
      s.passcode == pass);

  // ---- reports ----
  void setReports(List<EndOfDayReport> r) {
    reports = r;
    _persistReports();
    notifyListeners();
  }

  // ---- sync passthrough ----
  Future<SyncResult> triggerSync() async {
    final res = await _sync.triggerSync();
    lastSyncTime = _timeNow();
    notifyListeners();
    return res;
  }

  Future<Map<String, dynamic>> analyzeEod(
          List<Sale> todaySales, String date) =>
      _sync.analyzeEod(todaySales, date);

  /// Refreshes the local staff directory from Neon (best-effort). Call before
  /// validating a login so credentials are checked against the cloud database.
  Future<void> refreshStaff() async {
    final fresh = await _sync.fetchStaff();
    if (fresh != null && fresh.isNotEmpty) {
      staff = fresh;
      _persistStaff();
      notifyListeners();
    }
  }

  Future<bool> voidSaleRemote(String saleId) => _sync.voidSale(saleId);

  String _timeNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  // Mutators used by SyncService to overwrite local state with server master.
  void replaceProducts(List<Product> p) {
    // Guard: a bulk sync's product snapshot must not clobber a delete that is
    // still being written to Neon — that pre-change snapshot still contains the
    // deleted product and would resurrect it.
    if (_productWriteInFlight) return;
    products = p.map((x) => Product.fromJson(x.toJson())).toList();
    _persistProducts();
  }

  void replaceSales(List<Sale> s) {
    sales = s;
    _persistSales();
  }

  void replaceTransactions(List<StockTransaction> t) {
    transactions = t;
    _persistTransactions();
  }

  void replaceAuditLogs(List<AuditLog> a) {
    auditLogs = a;
    _persistAuditLogs();
  }

  void replaceReports(List<EndOfDayReport> r) {
    reports = r;
    _persistReports();
  }

  /// Merges (not overwrites) the incoming cloud/master loan list with what's
  /// already here. A blind replace let a stale or partial sync response
  /// silently revert a payment just recorded on this device, or drop a loan
  /// registered while offline that hadn't reached the server yet. Since
  /// amountPaid/originalAmount/payments only ever grow during normal use,
  /// "furthest along" reliably means "most up to date" on either side.
  void replaceLoans(List<Loan> incoming) {
    // Guard: don't let a bulk sync's loan snapshot resurrect a loan that is
    // currently being deleted on the server.
    if (_loanWriteInFlight) return;
    final localById = {for (final l in loans) l.id: l};
    final merged = <Loan>[];
    final seen = <String>{};
    for (final inc in incoming) {
      final local = localById[inc.id];
      if (local == null) {
        merged.add(inc);
      } else {
        final incomingIsFurtherAlong = inc.amountPaid >= local.amountPaid &&
            inc.originalAmount >= local.originalAmount &&
            inc.payments.length >= local.payments.length;
        merged.add(incomingIsFurtherAlong ? inc : local);
      }
      seen.add(inc.id);
    }
    // Keep local-only loans the server doesn't know about yet (e.g.
    // registered offline and not successfully pushed).
    for (final l in loans) {
      if (!seen.contains(l.id)) merged.add(l);
    }
    loans = merged;
    _persistLoans();
  }

  void replaceExpenses(List<Expense> e) {
    // Guard: don't let a bulk sync's expense snapshot resurrect an expense that
    // is currently being deleted on the server.
    if (_expenseWriteInFlight) return;
    expenses = e;
    _persistExpenses();
  }

  /// Drops any locally-held records the server reports as deleted (tombstoned).
  /// This is what makes a delete on one device (e.g. a Top Manager voiding a
  /// loan) propagate to another (e.g. a Manager) — the loan merge in
  /// [replaceLoans] otherwise keeps it as a "local-only" entry forever.
  void applyServerDeletions({
    List<String> sales = const [],
    List<String> products = const [],
    List<String> loans = const [],
    List<String> expenses = const [],
    List<String> categories = const [],
    List<String> expenseCategories = const [],
  }) {
    var changed = false;
    if (sales.isNotEmpty) {
      final ids = sales.toSet();
      final before = this.sales.length;
      this.sales.removeWhere((s) => ids.contains(s.id));
      if (this.sales.length != before) {
        _persistSales();
        changed = true;
      }
    }
    if (products.isNotEmpty) {
      final ids = products.toSet();
      final before = this.products.length;
      this.products.removeWhere((p) => ids.contains(p.id));
      if (this.products.length != before) {
        _persistProducts();
        changed = true;
      }
    }
    if (loans.isNotEmpty) {
      final ids = loans.toSet();
      final before = this.loans.length;
      this.loans.removeWhere((l) => ids.contains(l.id));
      if (this.loans.length != before) {
        _persistLoans();
        changed = true;
      }
    }
    if (expenses.isNotEmpty) {
      final ids = expenses.toSet();
      final before = this.expenses.length;
      this.expenses.removeWhere((e) => ids.contains(e.id));
      if (this.expenses.length != before) {
        _persistExpenses();
        changed = true;
      }
    }
    // Categories are bare strings, so they are dropped by value.
    if (categories.isNotEmpty) {
      final gone = categories.toSet();
      final before = this.categories.length;
      this.categories.removeWhere(gone.contains);
      if (this.categories.length != before) {
        _persistCategories();
        changed = true;
      }
    }
    if (expenseCategories.isNotEmpty) {
      final gone = expenseCategories.toSet();
      final before = this.expenseCategories.length;
      this.expenseCategories.removeWhere(gone.contains);
      if (this.expenseCategories.length != before) {
        _persistExpenseCategories();
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void replaceStaff(List<StaffProfile> s) {
    // Guard: never let a stray empty server response wipe local logins.
    if (s.isEmpty) return;
    // Guard: a bulk sync's staff snapshot must not clobber a staff create/edit/
    // delete that is still being pushed to Neon — that pre-change snapshot is
    // exactly what made new accounts disappear and deleted ones come back.
    if (_staffWriteInFlight) return;
    staff = s;
    _persistStaff();
  }

  // Local void (offline path)
  void voidSaleLocal(String saleId) {
    final idx = sales.indexWhere((s) => s.id == saleId);
    if (idx == -1) return;
    final voided = sales[idx];
    for (final item in voided.items) {
      final pIdx = products.indexWhere((p) => p.id == item.productId);
      if (pIdx != -1) products[pIdx].currentStock += item.quantity;
    }
    sales.removeAt(idx);
    _persistProducts();
    _persistSales();
    _log('SALE_VOID', 'Voided sale $saleId offline. Stock replenished.');
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
