// Domain models for Apex Retail Ledger.
// Ported faithfully from the original TypeScript `src/types.ts`.

enum UserRole { topManager, manager, worker }

extension UserRoleX on UserRole {
  String get wire {
    switch (this) {
      case UserRole.topManager:
        return 'top_manager';
      case UserRole.manager:
        return 'manager';
      case UserRole.worker:
        return 'worker';
    }
  }

  String get label {
    switch (this) {
      case UserRole.topManager:
        return 'Top Manager';
      case UserRole.manager:
        return 'Manager';
      case UserRole.worker:
        return 'Staff';
    }
  }

  bool get isManagerial =>
      this == UserRole.manager || this == UserRole.topManager;

  static UserRole fromWire(String? v) {
    switch (v) {
      case 'top_manager':
        return UserRole.topManager;
      case 'manager':
        return UserRole.manager;
      default:
        return UserRole.worker;
    }
  }
}

class Product {
  String id;
  String name;
  String sku;
  String category;
  num buyingPrice; // Staked cost (set)
  num sellingPrice; // Current sale price (adjustable any time, >= retailPrice)
  num wholesalePrice; // Minimum allowed selling price (floor). Not a customer-facing price tier.
  num retailPrice; // Default selling price per unit, shown at POS checkout.
  String unitLabel; // Unit name, e.g. 'piece', 'kg', 'litre'.
  num currentStock; // Always in base units (unitLabel).
  num minStockLevel; // Threshold for low stock alert
  String saleType; // 'retail' | 'wholesale'
  String? expirationDate; // YYYY-MM-DD
  String createdAt;
  bool? _isFavorite; // pinned to top of POS product grid

  /// Never null at runtime — defaults false for legacy / hot-reload rows.
  bool get isFavorite => _isFavorite ?? false;
  set isFavorite(bool value) => _isFavorite = value;

  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.buyingPrice,
    required this.sellingPrice,
    this.wholesalePrice = 0,
    num? retailPrice,
    this.unitLabel = 'piece',
    required this.currentStock,
    required this.minStockLevel,
    this.saleType = 'retail',
    required this.expirationDate,
    required this.createdAt,
    bool isFavorite = false,
  })  : retailPrice = retailPrice ?? wholesalePrice,
        _isFavorite = isFavorite;

  bool get isWholesale => saleType == 'wholesale';

  factory Product.fromJson(Map<String, dynamic> j) {
    // Back-compat: older rows only have 'minSellingPrice' (the old floor
    // field). Treat it as the wholesale price for those legacy records.
    final wholesale = j['wholesalePrice'] as num? ??
        j['minSellingPrice'] as num? ??
        (j['buyingPrice'] as num? ?? 0);
    return Product(
      id: j['id'] as String,
      name: j['name'] as String,
      sku: j['sku'] as String? ?? '',
      category: j['category'] as String? ?? 'General',
      buyingPrice: j['buyingPrice'] as num? ?? 0,
      sellingPrice: j['sellingPrice'] as num? ?? 0,
      wholesalePrice: wholesale,
      retailPrice: j['retailPrice'] as num? ?? wholesale,
      unitLabel: j['unitLabel'] as String? ?? 'piece',
      currentStock: j['currentStock'] as num? ?? 0,
      minStockLevel: j['minStockLevel'] as num? ?? 0,
      saleType: j['saleType'] as String? ?? 'retail',
      expirationDate: j['expirationDate'] as String?,
      createdAt: j['createdAt'] as String? ?? '',
      isFavorite: j['isFavorite'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'category': category,
        'buyingPrice': buyingPrice,
        'sellingPrice': sellingPrice,
        'wholesalePrice': wholesalePrice,
        'retailPrice': retailPrice,
        'unitLabel': unitLabel,
        'currentStock': currentStock,
        'minStockLevel': minStockLevel,
        'saleType': saleType,
        'expirationDate': expirationDate,
        'createdAt': createdAt,
        'isFavorite': isFavorite,
      };

  Product copy() => Product.fromJson(toJson());
}

class SaleItem {
  String id;
  String productId;
  String productName;
  num quantity;
  num buyingPrice;
  num sellingPrice;
  num totalBuyingPrice;
  num totalSellingPrice;
  num profit;

  SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.totalBuyingPrice,
    required this.totalSellingPrice,
    required this.profit,
  });

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        id: j['id'] as String? ?? '',
        productId: j['productId'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        quantity: j['quantity'] as num? ?? 0,
        buyingPrice: j['buyingPrice'] as num? ?? 0,
        sellingPrice: j['sellingPrice'] as num? ?? 0,
        totalBuyingPrice: j['totalBuyingPrice'] as num? ?? 0,
        totalSellingPrice: j['totalSellingPrice'] as num? ?? 0,
        profit: j['profit'] as num? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'buyingPrice': buyingPrice,
        'sellingPrice': sellingPrice,
        'totalBuyingPrice': totalBuyingPrice,
        'totalSellingPrice': totalSellingPrice,
        'profit': profit,
      };
}

class Sale {
  String id;
  List<SaleItem> items;
  num totalAmount;
  num totalBuyingPrice;
  num totalProfit;
  String paymentMethod; // 'cash' | 'mobile_money' | 'card' | 'partial'
  num amountPaid; // cash/settled portion actually received
  num changeDue;
  num loanAmount; // portion left unpaid as a loan (0 == fully paid)
  String? customerName; // required when there is a loan portion
  String? customerContact; // required when there is a loan portion
  String? loanPledgeDate; // YYYY-MM-DD, set only when loanAmount > 0
  String timestamp;
  String cashierId;
  String cashierName;
  bool synced;
  String? mobileMoneyTxId;

  Sale({
    required this.id,
    required this.items,
    required this.totalAmount,
    required this.totalBuyingPrice,
    required this.totalProfit,
    required this.paymentMethod,
    required this.amountPaid,
    required this.changeDue,
    this.loanAmount = 0,
    this.customerName,
    this.customerContact,
    this.loanPledgeDate,
    required this.timestamp,
    required this.cashierId,
    required this.cashierName,
    required this.synced,
    this.mobileMoneyTxId,
  });

  bool get hasLoan => loanAmount > 0;

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] as String,
        items: ((j['items'] as List?) ?? [])
            .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        totalAmount: j['totalAmount'] as num? ?? 0,
        totalBuyingPrice: j['totalBuyingPrice'] as num? ?? 0,
        totalProfit: j['totalProfit'] as num? ?? 0,
        paymentMethod: j['paymentMethod'] as String? ?? 'cash',
        amountPaid: j['amountPaid'] as num? ?? 0,
        changeDue: j['changeDue'] as num? ?? 0,
        loanAmount: j['loanAmount'] as num? ?? 0,
        customerName: j['customerName'] as String?,
        customerContact: j['customerContact'] as String?,
        loanPledgeDate: j['loanPledgeDate'] as String?,
        timestamp: j['timestamp'] as String? ?? '',
        cashierId: j['cashierId'] as String? ?? '',
        cashierName: j['cashierName'] as String? ?? '',
        synced: j['synced'] as bool? ?? false,
        mobileMoneyTxId: j['mobileMoneyTxId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items.map((e) => e.toJson()).toList(),
        'totalAmount': totalAmount,
        'totalBuyingPrice': totalBuyingPrice,
        'totalProfit': totalProfit,
        'paymentMethod': paymentMethod,
        'amountPaid': amountPaid,
        'changeDue': changeDue,
        'loanAmount': loanAmount,
        if (customerName != null) 'customerName': customerName,
        if (customerContact != null) 'customerContact': customerContact,
        if (loanPledgeDate != null) 'loanPledgeDate': loanPledgeDate,
        'timestamp': timestamp,
        'cashierId': cashierId,
        'cashierName': cashierName,
        'synced': synced,
        if (mobileMoneyTxId != null) 'mobileMoneyTxId': mobileMoneyTxId,
      };
}

/// A single repayment against a loan.
class LoanPayment {
  String id;
  num amount;
  String timestamp;
  String receivedById;
  String receivedByName;

  LoanPayment({
    required this.id,
    required this.amount,
    required this.timestamp,
    required this.receivedById,
    required this.receivedByName,
  });

  factory LoanPayment.fromJson(Map<String, dynamic> j) => LoanPayment(
        id: j['id'] as String,
        amount: j['amount'] as num? ?? 0,
        timestamp: j['timestamp'] as String? ?? '',
        receivedById: j['receivedById'] as String? ?? '',
        receivedByName: j['receivedByName'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'timestamp': timestamp,
        'receivedById': receivedById,
        'receivedByName': receivedByName,
      };
}

/// A credit/loan taken by a named customer with a pledged repayment date.
class Loan {
  String id;
  String customerName;
  String customerContact;
  num originalAmount;
  num amountPaid;
  String pledgeDate; // YYYY-MM-DD the customer pledged to pay by
  String createdAt;
  String createdById;
  String createdByName;
  String? saleId; // linked POS sale, if it originated from a checkout
  String? notes;
  String? settledAt; // ISO timestamp the loan was fully paid off, if settled
  num? profitRate; // profit fraction of the financed goods (0..1); cash-basis
  List<LoanPayment> payments;

  Loan({
    required this.id,
    required this.customerName,
    required this.customerContact,
    required this.originalAmount,
    required this.amountPaid,
    required this.pledgeDate,
    required this.createdAt,
    required this.createdById,
    required this.createdByName,
    this.saleId,
    this.notes,
    this.settledAt,
    this.profitRate = 0,
    List<LoanPayment>? payments,
  }) : payments = payments ?? [];

  num get balance => (originalAmount - amountPaid).clamp(0, double.infinity);
  bool get isSettled => balance <= 0;

  bool isOverdue([DateTime? now]) {
    if (isSettled) return false;
    final due = DateTime.tryParse(pledgeDate);
    if (due == null) return false;
    final today = now ?? DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  int daysUntilDue([DateTime? now]) {
    final due = DateTime.tryParse(pledgeDate);
    if (due == null) return 9999;
    final today = now ?? DateTime.now();
    return due.difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        id: j['id'] as String,
        customerName: j['customerName'] as String? ?? '',
        customerContact: j['customerContact'] as String? ?? '',
        originalAmount: j['originalAmount'] as num? ?? 0,
        amountPaid: j['amountPaid'] as num? ?? 0,
        pledgeDate: j['pledgeDate'] as String? ?? '',
        createdAt: j['createdAt'] as String? ?? '',
        createdById: j['createdById'] as String? ?? '',
        createdByName: j['createdByName'] as String? ?? '',
        saleId: j['saleId'] as String?,
        notes: j['notes'] as String?,
        settledAt: j['settledAt'] as String?,
        profitRate: j['profitRate'] as num? ?? 0,
        payments: ((j['payments'] as List?) ?? [])
            .map((e) => LoanPayment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerName': customerName,
        'customerContact': customerContact,
        'originalAmount': originalAmount,
        'amountPaid': amountPaid,
        'pledgeDate': pledgeDate,
        'createdAt': createdAt,
        'createdById': createdById,
        'createdByName': createdByName,
        if (saleId != null) 'saleId': saleId,
        if (notes != null) 'notes': notes,
        if (settledAt != null) 'settledAt': settledAt,
        'profitRate': profitRate ?? 0,
        // Explicit, denormalized settlement state so any other system reading
        // the loans table can see status/balance without recomputing them.
        'balance': balance,
        'settled': isSettled,
        'status': isSettled ? 'settled' : 'active',
        'payments': payments.map((e) => e.toJson()).toList(),
      };
}

/// A recorded business expenditure/cost.
class Expense {
  String id;
  String category;
  String description;
  num amount;
  String timestamp;
  String recordedById;
  String recordedByName;

  Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.timestamp,
    required this.recordedById,
    required this.recordedByName,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        category: j['category'] as String? ?? 'General',
        description: j['description'] as String? ?? '',
        amount: j['amount'] as num? ?? 0,
        timestamp: j['timestamp'] as String? ?? '',
        recordedById: j['recordedById'] as String? ?? '',
        recordedByName: j['recordedByName'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'description': description,
        'amount': amount,
        'timestamp': timestamp,
        'recordedById': recordedById,
        'recordedByName': recordedByName,
      };
}

class StockTransaction {
  String id;
  String productId;
  String productName;
  num quantity; // positive for in, negative for out
  String type; // 'in' | 'out'
  num buyingPriceAtTransaction;
  String timestamp;
  String operatorId;
  String operatorName;
  String reason; // restock | initial | sale | damaged | expired | audit_adjustment
  String? notes;

  StockTransaction({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.type,
    required this.buyingPriceAtTransaction,
    required this.timestamp,
    required this.operatorId,
    required this.operatorName,
    required this.reason,
    this.notes,
  });

  factory StockTransaction.fromJson(Map<String, dynamic> j) => StockTransaction(
        id: j['id'] as String,
        productId: j['productId'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        quantity: j['quantity'] as num? ?? 0,
        type: j['type'] as String? ?? 'in',
        buyingPriceAtTransaction: j['buyingPriceAtTransaction'] as num? ?? 0,
        timestamp: j['timestamp'] as String? ?? '',
        operatorId: j['operatorId'] as String? ?? '',
        operatorName: j['operatorName'] as String? ?? '',
        reason: j['reason'] as String? ?? 'restock',
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'type': type,
        'buyingPriceAtTransaction': buyingPriceAtTransaction,
        'timestamp': timestamp,
        'operatorId': operatorId,
        'operatorName': operatorName,
        'reason': reason,
        if (notes != null) 'notes': notes,
      };
}

class AuditLog {
  String id;
  String timestamp;
  String userId;
  String userName;
  UserRole userRole;
  String actionType;
  String details;

  AuditLog({
    required this.id,
    required this.timestamp,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.actionType,
    required this.details,
  });

  factory AuditLog.fromJson(Map<String, dynamic> j) => AuditLog(
        id: j['id'] as String,
        timestamp: j['timestamp'] as String? ?? '',
        userId: j['userId'] as String? ?? '',
        userName: j['userName'] as String? ?? '',
        userRole: UserRoleX.fromWire(j['userRole'] as String?),
        actionType: j['actionType'] as String? ?? '',
        details: j['details'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'userId': userId,
        'userName': userName,
        'userRole': userRole.wire,
        'actionType': actionType,
        'details': details,
      };
}

class UserSession {
  String userId;
  String name;
  UserRole role;

  UserSession({required this.userId, required this.name, required this.role});

  factory UserSession.fromJson(Map<String, dynamic> j) => UserSession(
        userId: j['userId'] as String? ?? '',
        name: j['name'] as String? ?? 'Not signed in',
        role: UserRoleX.fromWire(j['role'] as String?),
      );

  Map<String, dynamic> toJson() =>
      {'userId': userId, 'name': name, 'role': role.wire};
}

class StaffProfile {
  String userId;
  String name;
  UserRole role;
  String passcode;

  StaffProfile({
    required this.userId,
    required this.name,
    required this.role,
    required this.passcode,
  });

  factory StaffProfile.fromJson(Map<String, dynamic> j) => StaffProfile(
        userId: j['userId'] as String,
        name: j['name'] as String? ?? '',
        role: UserRoleX.fromWire(j['role'] as String?),
        passcode: j['passcode'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'userId': userId, 'name': name, 'role': role.wire, 'passcode': passcode};
}

class EndOfDayReport {
  String id;
  String date;
  num totalSales;
  num totalProfit;
  num totalStaked;
  num salesCount;
  String reportDrawnBy;
  String reportDrawnAt;
  bool ownerNotificationSent;
  String ownerContact;
  String? aiInsights; // JSON string

  EndOfDayReport({
    required this.id,
    required this.date,
    required this.totalSales,
    required this.totalProfit,
    required this.totalStaked,
    required this.salesCount,
    required this.reportDrawnBy,
    required this.reportDrawnAt,
    required this.ownerNotificationSent,
    required this.ownerContact,
    this.aiInsights,
  });

  factory EndOfDayReport.fromJson(Map<String, dynamic> j) => EndOfDayReport(
        id: j['id'] as String,
        date: j['date'] as String? ?? '',
        totalSales: j['totalSales'] as num? ?? 0,
        totalProfit: j['totalProfit'] as num? ?? 0,
        totalStaked: j['totalStaked'] as num? ?? 0,
        salesCount: j['salesCount'] as num? ?? 0,
        reportDrawnBy: j['reportDrawnBy'] as String? ?? '',
        reportDrawnAt: j['reportDrawnAt'] as String? ?? '',
        ownerNotificationSent: j['ownerNotificationSent'] as bool? ?? false,
        ownerContact: j['ownerContact'] as String? ?? '',
        aiInsights: j['aiInsights'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'totalSales': totalSales,
        'totalProfit': totalProfit,
        'totalStaked': totalStaked,
        'salesCount': salesCount,
        'reportDrawnBy': reportDrawnBy,
        'reportDrawnAt': reportDrawnAt,
        'ownerNotificationSent': ownerNotificationSent,
        'ownerContact': ownerContact,
        if (aiInsights != null) 'aiInsights': aiInsights,
      };
}

class PrinterSettings {
  String paperWidth; // '58mm' | '80mm'
  String ipAddress;
  String bluetoothAddress;
  String defaultFormat; // 'receipt' | 'sticker'

  PrinterSettings({
    required this.paperWidth,
    required this.ipAddress,
    required this.bluetoothAddress,
    required this.defaultFormat,
  });

  factory PrinterSettings.fromJson(Map<String, dynamic> j) => PrinterSettings(
        paperWidth: j['paperWidth'] as String? ?? '80mm',
        ipAddress: j['ipAddress'] as String? ?? '',
        bluetoothAddress: j['bluetoothAddress'] as String? ?? '',
        defaultFormat: j['defaultFormat'] as String? ?? 'receipt',
      );

  Map<String, dynamic> toJson() => {
        'paperWidth': paperWidth,
        'ipAddress': ipAddress,
        'bluetoothAddress': bluetoothAddress,
        'defaultFormat': defaultFormat,
      };
}
