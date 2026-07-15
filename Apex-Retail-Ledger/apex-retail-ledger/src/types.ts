export interface Product {
  id: string;
  name: string;
  sku: string;
  category: string;
  buyingPrice: number; // Staked / cost price
  sellingPrice: number; // Default sale price (legacy field, mirrors retailPrice)
  // Cloud/Flutter parity fields. Optional so legacy web products still type-check;
  // helpers below fall back to sellingPrice when they are absent.
  wholesalePrice?: number; // "Limit price" — the POS floor a sale may not go below
  retailPrice?: number; // Default sale price shown at POS
  unitLabel?: string; // e.g. piece, kg, litre
  currentStock: number;
  minStockLevel: number; // Threshold for low stock alert
  expirationDate: string | null; // YYYY-MM-DD
  createdAt: string;
  isFavorite?: boolean;
}

/** The POS floor for a product: its limit price (falls back to selling price). */
export const productLimit = (p: Product): number =>
  (p.wholesalePrice ?? p.retailPrice ?? p.sellingPrice) || 0;

/** The default sale price for a product (falls back to selling price). */
export const productSalePrice = (p: Product): number =>
  (p.retailPrice ?? p.sellingPrice) || 0;

export interface SaleItem {
  id: string;
  productId: string;
  productName: string;
  quantity: number;
  buyingPrice: number; // At time of sale
  sellingPrice: number; // At time of sale
  totalBuyingPrice: number;
  totalSellingPrice: number;
  profit: number;
}

export interface Sale {
  id: string;
  items: SaleItem[];
  totalAmount: number;
  totalBuyingPrice: number;
  totalProfit: number;
  paymentMethod: 'cash' | 'mobile_money' | 'card' | 'partial';
  amountPaid: number;
  changeDue: number;
  loanAmount?: number; // unpaid balance taken on credit at checkout
  customerName?: string; // required when part of the sale is on loan
  customerContact?: string;
  loanPledgeDate?: string; // YYYY-MM-DD the customer pledged to repay by
  timestamp: string;
  cashierId: string;
  cashierName: string;
  synced: boolean;
  mobileMoneyTxId?: string;
}

export interface LoanPayment {
  id: string;
  amount: number;
  timestamp: string;
  receivedById: string;
  receivedByName: string;
}

export interface Loan {
  id: string;
  customerName: string;
  customerContact: string;
  originalAmount: number;
  amountPaid: number;
  pledgeDate: string; // YYYY-MM-DD
  createdAt: string;
  createdById: string;
  createdByName: string;
  saleId?: string; // linked POS sale, if it originated from a checkout
  notes?: string;
  settledAt?: string; // ISO timestamp the loan was fully paid off
  profitRate?: number; // profit fraction of financed goods (cash-basis)
  payments: LoanPayment[];
}

export const loanBalance = (l: Loan): number =>
  Math.max(0, l.originalAmount - l.amountPaid);
export const loanSettled = (l: Loan): boolean => loanBalance(l) <= 0;

export interface Expense {
  id: string;
  category: string;
  description: string;
  amount: number;
  timestamp: string;
  recordedById: string;
  recordedByName: string;
}

export interface StaffProfile {
  userId: string;
  name: string;
  role: 'top_manager' | 'manager' | 'worker';
  passcode: string;
}

export interface StockTransaction {
  id: string;
  productId: string;
  productName: string;
  quantity: number; // positive for stock in, negative for stock out (waste, adjustment)
  type: 'in' | 'out';
  buyingPriceAtTransaction: number;
  timestamp: string;
  operatorId: string;
  operatorName: string;
  reason: 'restock' | 'initial' | 'sale' | 'damaged' | 'expired' | 'audit_adjustment';
  notes?: string;
}

export interface AuditLog {
  id: string;
  timestamp: string;
  userId: string;
  userName: string;
  userRole: 'top_manager' | 'manager' | 'worker';
  actionType: string; // 'LOGIN' | 'STOCK_IN' | 'SALE' | 'SYNC' | 'EOD_BALANCE' | 'PRODUCT_CREATE' | 'PRODUCT_UPDATE'
  details: string;
}

export interface UserSession {
  userId: string;
  name: string;
  role: 'top_manager' | 'manager' | 'worker';
}

export interface EndOfDayReport {
  id: string;
  date: string;
  totalSales: number;
  totalProfit: number;
  totalStaked: number; // Total cost of inventory sold
  salesCount: number;
  reportDrawnBy: string;
  reportDrawnAt: string;
  ownerNotificationSent: boolean;
  ownerContact: string;
  aiInsights?: string;
}

export interface SyncDataPayload {
  sales: Sale[];
  products: Product[];
  stockTransactions: StockTransaction[];
  auditLogs: AuditLog[];
  reports: EndOfDayReport[];
  loans?: Loan[];
  expenses?: Expense[];
  staff?: StaffProfile[];
}

/** Tombstoned ids returned by /api/sync so clients drop deleted records. */
export interface SyncDeletions {
  sales?: string[];
  products?: string[];
  loans?: string[];
  expenses?: string[];
}

export interface PrinterSettings {
  paperWidth: '58mm' | '80mm';
  ipAddress: string;
  bluetoothAddress: string;
  defaultFormat: 'receipt' | 'sticker';
}

