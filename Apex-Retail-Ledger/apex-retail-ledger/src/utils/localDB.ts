import { Product, Sale, StockTransaction, AuditLog, UserSession, EndOfDayReport, SyncDataPayload, PrinterSettings, Loan, LoanPayment, Expense, loanBalance, loanSettled } from '../types';

// Helper to generate IDs
export const generateId = () => Math.random().toString(36).substring(2, 11).toUpperCase();

// No demo catalog — the system starts empty and is populated only with real
// data, which syncs to the Neon cloud database via /api/sync.
const DEFAULT_PRODUCTS: Product[] = [];

// No seeded sales, stock movements, or audit trail. These start empty and grow
// from real activity.
const seedSales = (): Sale[] => [];
const seedStockTransactions = (): StockTransaction[] => [];
const seedAuditLogs = (): AuditLog[] => [];

// Local storage keys
const KEYS = {
  PRODUCTS: 'sm_products',
  SALES: 'sm_sales',
  TRANSACTIONS: 'sm_transactions',
  AUDIT_LOGS: 'sm_audit_logs',
  REPORTS: 'sm_reports',
  LOANS: 'sm_loans',
  EXPENSES: 'sm_expenses',
  SESSION: 'sm_session',
  OFFLINE_MODE: 'sm_offline_mode',
  PENDING_SYNC: 'sm_pending_sync',
  MANAGER_PASSWORD: 'sm_manager_password',
  STAFF_PROFILES: 'sm_staff_profiles',
  EXPIRED_CONTROL: 'sm_expired_control',
  CATEGORIES: 'sm_categories',
  PRINTER_SETTINGS: 'sm_printer_settings'
};

// Memory cache for sub-millisecond retrieval and absolute zero freezing
const cache: Record<string, any> = {};

export const localDB = {
  // Initialize with seed data if empty
  init: () => {
    if (!localStorage.getItem(KEYS.PRODUCTS)) {
      localStorage.setItem(KEYS.PRODUCTS, JSON.stringify(DEFAULT_PRODUCTS));
    }
    if (!localStorage.getItem(KEYS.SALES)) {
      localStorage.setItem(KEYS.SALES, JSON.stringify(seedSales()));
    }
    if (!localStorage.getItem(KEYS.TRANSACTIONS)) {
      localStorage.setItem(KEYS.TRANSACTIONS, JSON.stringify(seedStockTransactions()));
    }
    if (!localStorage.getItem(KEYS.AUDIT_LOGS)) {
      localStorage.setItem(KEYS.AUDIT_LOGS, JSON.stringify(seedAuditLogs()));
    }
    if (!localStorage.getItem(KEYS.REPORTS)) {
      localStorage.setItem(KEYS.REPORTS, JSON.stringify([]));
    }
    if (!localStorage.getItem(KEYS.LOANS)) {
      localStorage.setItem(KEYS.LOANS, JSON.stringify([]));
    }
    if (!localStorage.getItem(KEYS.EXPENSES)) {
      localStorage.setItem(KEYS.EXPENSES, JSON.stringify([]));
    }
    if (!localStorage.getItem(KEYS.SESSION)) {
      localStorage.setItem(KEYS.SESSION, JSON.stringify({ userId: '', name: 'Not signed in', role: 'worker' }));
    }
    if (localStorage.getItem(KEYS.OFFLINE_MODE) === null) {
      localStorage.setItem(KEYS.OFFLINE_MODE, 'false');
    }
    if (!localStorage.getItem(KEYS.MANAGER_PASSWORD)) {
      localStorage.setItem(KEYS.MANAGER_PASSWORD, '2468');
    }
    if (!localStorage.getItem(KEYS.STAFF_PROFILES)) {
      // Single bootstrap owner only — matches the owner seeded in Neon. The real
      // staff list is pulled from the cloud database on first sync.
      const defaultStaff = [
        { userId: 'TM001', name: 'Jude', role: 'top_manager', passcode: '2468' }
      ];
      localStorage.setItem(KEYS.STAFF_PROFILES, JSON.stringify(defaultStaff));
    }
    if (!localStorage.getItem(KEYS.EXPIRED_CONTROL)) {
      localStorage.setItem(KEYS.EXPIRED_CONTROL, 'restrict');
    }
    if (!localStorage.getItem(KEYS.CATEGORIES)) {
      const initialCats = [
        'Seeds',
        'Fertilizers',
        'Irrigation',
        'Livestock',
        'Pesticides',
        'Herbicides',
        'Farming Tools',
        'Farmer Organic Solutions',
        'Fungicides',
        'Seedlings and Cuttings',
      ];
      localStorage.setItem(KEYS.CATEGORIES, JSON.stringify(initialCats));
    }
    if (!localStorage.getItem(KEYS.PRINTER_SETTINGS)) {
      const defaultPrinter: PrinterSettings = {
        paperWidth: '80mm',
        ipAddress: '192.168.1.100',
        bluetoothAddress: '00:11:22:33:FF:EE',
        defaultFormat: 'receipt'
      };
      localStorage.setItem(KEYS.PRINTER_SETTINGS, JSON.stringify(defaultPrinter));
    }

    // One-time purge of legacy demo/seed data that older installs cached before
    // the demo data was removed. Guarded by a data-version flag; targeted to the
    // demo signature so any real data already entered is preserved. Demo products
    // use ids P001–P010 (real ones are P100+); the test artifact used sku REAL-1;
    // demo audit logs / staff came from the removed M001 / W001 / W002 accounts.
    const DATA_VERSION = '2';
    if (localStorage.getItem('sm_data_version') !== DATA_VERSION) {
      const isDemoId = (id: string) => /^P0\d\d$/.test(id || '');
      const demoUsers = ['M001', 'W001', 'W002'];
      const read = (k: string) => JSON.parse(localStorage.getItem(k) || '[]');
      localStorage.setItem(KEYS.PRODUCTS, JSON.stringify(
        read(KEYS.PRODUCTS).filter((p: any) => !isDemoId(p.id) && p.sku !== 'REAL-1')));
      localStorage.setItem(KEYS.TRANSACTIONS, JSON.stringify(
        read(KEYS.TRANSACTIONS).filter((t: any) => !isDemoId(t.productId))));
      localStorage.setItem(KEYS.SALES, JSON.stringify(
        read(KEYS.SALES).filter((s: any) => !(s.items || []).some((it: any) => isDemoId(it.productId)))));
      localStorage.setItem(KEYS.AUDIT_LOGS, JSON.stringify(
        read(KEYS.AUDIT_LOGS).filter((l: any) => !demoUsers.includes(l.userId))));
      const cleanStaff = read(KEYS.STAFF_PROFILES).filter((s: any) => !demoUsers.includes(s.userId));
      if (cleanStaff.length > 0) localStorage.setItem(KEYS.STAFF_PROFILES, JSON.stringify(cleanStaff));
      localStorage.setItem('sm_data_version', DATA_VERSION);
      // Drop cache so the warm-up below reloads the cleaned lists.
      [KEYS.PRODUCTS, KEYS.TRANSACTIONS, KEYS.SALES, KEYS.AUDIT_LOGS, KEYS.STAFF_PROFILES].forEach(k => { delete cache[k]; });
    }

    // Warm up the memory cache
    if (!cache[KEYS.PRODUCTS]) cache[KEYS.PRODUCTS] = JSON.parse(localStorage.getItem(KEYS.PRODUCTS) || '[]');
    if (!cache[KEYS.SALES]) cache[KEYS.SALES] = JSON.parse(localStorage.getItem(KEYS.SALES) || '[]');
    if (!cache[KEYS.TRANSACTIONS]) cache[KEYS.TRANSACTIONS] = JSON.parse(localStorage.getItem(KEYS.TRANSACTIONS) || '[]');
    if (!cache[KEYS.AUDIT_LOGS]) cache[KEYS.AUDIT_LOGS] = JSON.parse(localStorage.getItem(KEYS.AUDIT_LOGS) || '[]');
    if (!cache[KEYS.REPORTS]) cache[KEYS.REPORTS] = JSON.parse(localStorage.getItem(KEYS.REPORTS) || '[]');
    if (!cache[KEYS.LOANS]) cache[KEYS.LOANS] = JSON.parse(localStorage.getItem(KEYS.LOANS) || '[]');
    if (!cache[KEYS.EXPENSES]) cache[KEYS.EXPENSES] = JSON.parse(localStorage.getItem(KEYS.EXPENSES) || '[]');
    if (!cache[KEYS.SESSION]) cache[KEYS.SESSION] = JSON.parse(localStorage.getItem(KEYS.SESSION) || 'null');
    if (!cache[KEYS.STAFF_PROFILES]) cache[KEYS.STAFF_PROFILES] = JSON.parse(localStorage.getItem(KEYS.STAFF_PROFILES) || '[]');
    if (cache[KEYS.OFFLINE_MODE] === undefined) cache[KEYS.OFFLINE_MODE] = localStorage.getItem(KEYS.OFFLINE_MODE) === 'true';
    if (!cache[KEYS.MANAGER_PASSWORD]) cache[KEYS.MANAGER_PASSWORD] = localStorage.getItem(KEYS.MANAGER_PASSWORD) || '2468';
    if (!cache[KEYS.EXPIRED_CONTROL]) cache[KEYS.EXPIRED_CONTROL] = localStorage.getItem(KEYS.EXPIRED_CONTROL) || 'restrict';
    if (!cache[KEYS.CATEGORIES]) cache[KEYS.CATEGORIES] = JSON.parse(localStorage.getItem(KEYS.CATEGORIES) || '[]');
    if (!cache[KEYS.PRINTER_SETTINGS]) cache[KEYS.PRINTER_SETTINGS] = JSON.parse(localStorage.getItem(KEYS.PRINTER_SETTINGS) || 'null');
  },

  // Getters
  getProducts: (): Product[] => {
    localDB.init();
    return cache[KEYS.PRODUCTS];
  },

  getSales: (): Sale[] => {
    localDB.init();
    return cache[KEYS.SALES];
  },

  getTransactions: (): StockTransaction[] => {
    localDB.init();
    return cache[KEYS.TRANSACTIONS];
  },

  getAuditLogs: (): AuditLog[] => {
    localDB.init();
    return cache[KEYS.AUDIT_LOGS];
  },

  getReports: (): EndOfDayReport[] => {
    localDB.init();
    return cache[KEYS.REPORTS];
  },

  getCategories: (): string[] => {
    localDB.init();
    return cache[KEYS.CATEGORIES];
  },

  getPrinterSettings: (): PrinterSettings => {
    localDB.init();
    if (!cache[KEYS.PRINTER_SETTINGS]) {
      return {
        paperWidth: '80mm',
        ipAddress: '192.168.1.100',
        bluetoothAddress: '00:11:22:33:FF:EE',
        defaultFormat: 'receipt'
      };
    }
    return cache[KEYS.PRINTER_SETTINGS];
  },

  setPrinterSettings: (settings: PrinterSettings) => {
    cache[KEYS.PRINTER_SETTINGS] = settings;
    localStorage.setItem(KEYS.PRINTER_SETTINGS, JSON.stringify(settings));
  },

  setCategories: (categories: string[]) => {
    cache[KEYS.CATEGORIES] = categories;
    localStorage.setItem(KEYS.CATEGORIES, JSON.stringify(categories));
  },

  addCategory: (category: string): boolean => {
    const categories = localDB.getCategories();
    const normalized = category.trim();
    if (normalized && !categories.includes(normalized)) {
      categories.push(normalized);
      localDB.setCategories(categories);
      const session = localDB.getSession();
      localDB.logAction(session.userId, session.name, session.role, 'CATEGORY_CREATE', `Created category: ${normalized}`);
      return true;
    }
    return false;
  },

  editCategory: (oldName: string, newName: string): boolean => {
    const categories = localDB.getCategories();
    const oldIndex = categories.indexOf(oldName);
    const normalizedNew = newName.trim();
    if (oldIndex !== -1 && normalizedNew && !categories.includes(normalizedNew)) {
      categories[oldIndex] = normalizedNew;
      localDB.setCategories(categories);
      
      // Update all products in this category
      const products = localDB.getProducts();
      let updatedCount = 0;
      products.forEach(p => {
        if (p.category === oldName) {
          p.category = normalizedNew;
          updatedCount++;
        }
      });
      if (updatedCount > 0) {
        localDB.setProducts(products);
      }
      
      const session = localDB.getSession();
      localDB.logAction(session.userId, session.name, session.role, 'CATEGORY_UPDATE', `Edited category ${oldName} -> ${normalizedNew}. Re-assigned ${updatedCount} products.`);
      return true;
    }
    return false;
  },

  deleteCategory: (category: string, fallbackCategory: string = 'General'): boolean => {
    const categories = localDB.getCategories();
    const index = categories.indexOf(category);
    if (index !== -1) {
      categories.splice(index, 1);
      
      // Ensure fallbackCategory exists in categories
      if (!categories.includes(fallbackCategory)) {
        categories.push(fallbackCategory);
      }
      localDB.setCategories(categories);
      
      // Update all products in this category to fallbackCategory
      const products = localDB.getProducts();
      let updatedCount = 0;
      products.forEach(p => {
        if (p.category === category) {
          p.category = fallbackCategory;
          updatedCount++;
        }
      });
      if (updatedCount > 0) {
        localDB.setProducts(products);
      }
      
      const session = localDB.getSession();
      localDB.logAction(session.userId, session.name, session.role, 'CATEGORY_DELETE', `Deleted category ${category}. Re-assigned ${updatedCount} products to ${fallbackCategory}.`);
      return true;
    }
    return false;
  },

  getSession: (): UserSession => {
    localDB.init();
    return cache[KEYS.SESSION] || { userId: '', name: 'Not signed in', role: 'worker' };
  },

  isOfflineMode: (): boolean => {
    localDB.init();
    return cache[KEYS.OFFLINE_MODE];
  },

  getManagerPassword: (): string => {
    localDB.init();
    return cache[KEYS.MANAGER_PASSWORD];
  },

  setManagerPassword: (password: string) => {
    cache[KEYS.MANAGER_PASSWORD] = password;
    localStorage.setItem(KEYS.MANAGER_PASSWORD, password);
  },

  getStaffProfiles: (): any[] => {
    localDB.init();
    return cache[KEYS.STAFF_PROFILES];
  },

  // Adopts the server's authoritative staff list WITHOUT pushing a diff back
  // (used when a sync pull returns the master directory).
  setStaffProfilesLocal: (profiles: any[]) => {
    if (!profiles || profiles.length === 0) return; // never let an empty response wipe logins
    cache[KEYS.STAFF_PROFILES] = profiles;
    localStorage.setItem(KEYS.STAFF_PROFILES, JSON.stringify(profiles));
  },

  setStaffProfiles: (profiles: any[]) => {
    const before: any[] = cache[KEYS.STAFF_PROFILES] || [];
    cache[KEYS.STAFF_PROFILES] = profiles;
    localStorage.setItem(KEYS.STAFF_PROFILES, JSON.stringify(profiles));
    // Propagate to the authoritative Neon staff directory (staff is never
    // carried by the bulk sync). Best-effort; the server rejects these with 403
    // unless the caller is an authenticated manager, so the pull done at login
    // time is a harmless no-op.
    void localDB._syncStaffDiff(before, profiles);
  },

  _syncStaffDiff: async (before: any[], after: any[]) => {
    if (localDB.isOfflineMode()) return;
    const role = (localDB.getSession()?.role) || 'worker';
    const afterIds = new Set(after.map(s => s.userId));
    const post = (path: string, body: any) =>
      fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).catch(() => {});
    for (const o of before) {
      if (!afterIds.has(o.userId)) await post('/api/staff/delete', { userId: o.userId, role });
    }
    for (const n of after) {
      const prev = before.find(o => o.userId === n.userId);
      if (!prev || JSON.stringify(prev) !== JSON.stringify(n)) {
        await post('/api/staff/save', { staff: n, role });
      }
    }
  },

  getExpiredSalesControl: (): 'restrict' | 'allow' => {
    localDB.init();
    return cache[KEYS.EXPIRED_CONTROL];
  },

  setExpiredSalesControl: (control: 'restrict' | 'allow') => {
    cache[KEYS.EXPIRED_CONTROL] = control;
    localStorage.setItem(KEYS.EXPIRED_CONTROL, control);
  },

  // Setters
  setProducts: (products: Product[]) => {
    cache[KEYS.PRODUCTS] = products;
    localStorage.setItem(KEYS.PRODUCTS, JSON.stringify(products));
  },

  setSales: (sales: Sale[]) => {
    cache[KEYS.SALES] = sales;
    localStorage.setItem(KEYS.SALES, JSON.stringify(sales));
  },

  setTransactions: (transactions: StockTransaction[]) => {
    cache[KEYS.TRANSACTIONS] = transactions;
    localStorage.setItem(KEYS.TRANSACTIONS, JSON.stringify(transactions));
  },

  setReports: (reports: EndOfDayReport[]) => {
    cache[KEYS.REPORTS] = reports;
    localStorage.setItem(KEYS.REPORTS, JSON.stringify(reports));
  },

  // ---- Loans / credit ----
  getLoans: (): Loan[] => {
    localDB.init();
    return cache[KEYS.LOANS];
  },

  setLoans: (loans: Loan[]) => {
    cache[KEYS.LOANS] = loans;
    localStorage.setItem(KEYS.LOANS, JSON.stringify(loans));
  },

  // Registers a credit balance against a customer. Called from POS checkout when
  // part of a sale is unpaid. `profitRate` carries the sale margin so profit on
  // the credit portion is recognised (cash-basis) as the loan is repaid.
  addLoan: (data: {
    customerName: string;
    customerContact: string;
    amount: number;
    pledgeDate: string;
    saleId?: string;
    notes?: string;
    profitRate?: number;
  }): Loan => {
    const loans = localDB.getLoans();
    const session = localDB.getSession();
    const loan: Loan = {
      id: 'LN-' + Math.floor(10000 + Math.random() * 90000),
      customerName: data.customerName,
      customerContact: data.customerContact,
      originalAmount: data.amount,
      amountPaid: 0,
      pledgeDate: data.pledgeDate,
      createdAt: new Date().toISOString(),
      createdById: session.userId,
      createdByName: session.name,
      saleId: data.saleId,
      notes: data.notes,
      profitRate: data.profitRate ?? 0,
      payments: []
    };
    loans.unshift(loan);
    localDB.setLoans(loans);
    localDB.logAction(session.userId, session.name, session.role, 'LOAN_CREATE',
      `Registered loan of shs ${data.amount.toLocaleString()} for ${data.customerName} (due ${data.pledgeDate})`);
    if (!localDB.isOfflineMode()) {
      localDB.triggerSync().catch(() => {});
    }
    return loan;
  },

  recordLoanPayment: (loanId: string, amount: number) => {
    const loans = localDB.getLoans();
    const loan = loans.find(l => l.id === loanId);
    if (!loan || amount <= 0) return;
    const applied = Math.min(amount, loanBalance(loan));
    loan.amountPaid += applied;
    const session = localDB.getSession();
    const payment: LoanPayment = {
      id: generateId(),
      amount: applied,
      timestamp: new Date().toISOString(),
      receivedById: session.userId,
      receivedByName: session.name
    };
    loan.payments.unshift(payment);
    const justSettled = loanSettled(loan) && !loan.settledAt;
    if (justSettled) loan.settledAt = new Date().toISOString();
    localDB.setLoans(loans);
    localDB.logAction(session.userId, session.name, session.role, 'LOAN_PAYMENT',
      `Received shs ${applied.toLocaleString()} on loan ${loan.id} (${loan.customerName}). Balance: shs ${loanBalance(loan).toLocaleString()}`);
    if (justSettled) {
      localDB.logAction(session.userId, session.name, session.role, 'LOAN_SETTLED',
        `Loan ${loan.id} (${loan.customerName}) fully settled — total ${loan.originalAmount.toLocaleString()} paid off.`);
    }
    if (!localDB.isOfflineMode()) {
      localDB.triggerSync().catch(() => {});
    }
  },

  deleteLoan: async (loanId: string) => {
    const loans = localDB.getLoans().filter(l => l.id !== loanId);
    localDB.setLoans(loans);
    const session = localDB.getSession();
    localDB.logAction(session.userId, session.name, session.role, 'LOAN_DELETE', `Deleted loan record ${loanId}`);
    if (localDB.isOfflineMode()) return;
    try {
      const res = await fetch('/api/loans/delete', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ loanId, role: session.role })
      });
      const data = await res.json().catch(() => null);
      if (res.ok && data?.success && data.loans) localDB.setLoans(data.loans);
    } catch { /* offline — local removal stands */ }
  },

  // ---- Expenses ----
  getExpenses: (): Expense[] => {
    localDB.init();
    return cache[KEYS.EXPENSES];
  },

  setExpenses: (expenses: Expense[]) => {
    cache[KEYS.EXPENSES] = expenses;
    localStorage.setItem(KEYS.EXPENSES, JSON.stringify(expenses));
  },

  addExpense: (data: { category: string; description: string; amount: number }): Expense => {
    const expenses = localDB.getExpenses();
    const session = localDB.getSession();
    const expense: Expense = {
      id: 'EXP-' + Math.floor(10000 + Math.random() * 90000),
      category: data.category,
      description: data.description,
      amount: data.amount,
      timestamp: new Date().toISOString(),
      recordedById: session.userId,
      recordedByName: session.name
    };
    expenses.unshift(expense);
    localDB.setExpenses(expenses);
    localDB.logAction(session.userId, session.name, session.role, 'EXPENSE_RECORD',
      `Recorded ${data.category} expense of shs ${data.amount.toLocaleString()}: ${data.description}`);
    if (!localDB.isOfflineMode()) {
      localDB.triggerSync().catch(() => {});
    }
    return expense;
  },

  deleteExpense: async (id: string) => {
    const expenses = localDB.getExpenses().filter(e => e.id !== id);
    localDB.setExpenses(expenses);
    const session = localDB.getSession();
    localDB.logAction(session.userId, session.name, session.role, 'EXPENSE_DELETE', `Deleted expense ${id}`);
    if (localDB.isOfflineMode()) return;
    try {
      const res = await fetch('/api/expenses/delete', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ expenseId: id, role: session.role })
      });
      const data = await res.json().catch(() => null);
      if (res.ok && data?.success && data.expenses) localDB.setExpenses(data.expenses);
    } catch { /* offline — local removal stands */ }
  },

  // Authoritative product delete (Top Manager). Bulk sync only upserts products,
  // so a deletion must go through this route or it reappears on the next pull.
  deleteProduct: async (productId: string) => {
    const products = localDB.getProducts().filter(p => p.id !== productId);
    localDB.setProducts(products);
    const session = localDB.getSession();
    localDB.logAction(session.userId, session.name, session.role, 'PRODUCT_DELETE', `Deleted commodity ${productId}`);
    if (localDB.isOfflineMode()) return;
    try {
      const res = await fetch('/api/products/delete', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ productId, role: session.role })
      });
      const data = await res.json().catch(() => null);
      if (res.ok && data?.success && data.products) localDB.setProducts(data.products);
    } catch { /* offline — local removal stands */ }
  },

  setSession: (session: UserSession) => {
    cache[KEYS.SESSION] = session;
    localStorage.setItem(KEYS.SESSION, JSON.stringify(session));
    localDB.logAction(session.userId, session.name, session.role, 'LOGIN', `${session.role === 'manager' ? 'Manager' : 'Worker'} session initialized: ${session.name}`);
  },

  setOfflineMode: (offline: boolean) => {
    cache[KEYS.OFFLINE_MODE] = offline;
    localStorage.setItem(KEYS.OFFLINE_MODE, String(offline));
    const session = localDB.getSession();
    localDB.logAction(session.userId, session.name, session.role, 'SYNC', `Offline mode toggled to ${offline}`);
  },

  // Core Actions
  addProduct: (product: Omit<Product, 'id' | 'createdAt'>): Product => {
    const products = localDB.getProducts();
    let sku = product.sku ? product.sku.trim() : '';
    if (!sku) {
      const catCode = product.category
        ? product.category.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 3)
        : 'GEN';
      const cleanName = product.name
        ? product.name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase()
        : 'PRD';
      const randomNum = Math.floor(100000 + Math.random() * 900000); // 6-digit random number
      sku = `${catCode}-${cleanName}-${randomNum}`;
    }
    const newProduct: Product = {
      ...product,
      sku,
      id: 'P' + Math.floor(100 + Math.random() * 900).toString(),
      createdAt: new Date().toISOString()
    };
    products.push(newProduct);
    localDB.setProducts(products);

    // Audit and Stock Transaction
    const session = localDB.getSession();
    localDB.logAction(session.userId, session.name, session.role, 'PRODUCT_CREATE', `Created product: ${newProduct.name} (SKU: ${newProduct.sku})`);
    
    localDB.addTransaction({
      productId: newProduct.id,
      productName: newProduct.name,
      quantity: newProduct.currentStock,
      type: 'in',
      buyingPriceAtTransaction: newProduct.buyingPrice,
      reason: 'initial',
      notes: 'Initial stock setup'
    });

    return newProduct;
  },

  updateProduct: (updated: Product) => {
    const products = localDB.getProducts();
    const index = products.findIndex(p => p.id === updated.id);
    if (index !== -1) {
      let finalSku = updated.sku ? updated.sku.trim() : '';
      if (!finalSku) {
        const catCode = updated.category
          ? updated.category.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 3)
          : 'GEN';
        const cleanName = updated.name
          ? updated.name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase()
          : 'PRD';
        const randomNum = Math.floor(100000 + Math.random() * 900000);
        finalSku = `${catCode}-${cleanName}-${randomNum}`;
      }
      const updatedWithSku = { ...updated, sku: finalSku };
      const original = products[index];
      products[index] = updatedWithSku;
      localDB.setProducts(products);

      const session = localDB.getSession();
      
      // Stock adjustment detection
      const diff = updatedWithSku.currentStock - original.currentStock;
      if (diff !== 0) {
        localDB.addTransaction({
          productId: updatedWithSku.id,
          productName: updatedWithSku.name,
          quantity: diff,
          type: diff > 0 ? 'in' : 'out',
          buyingPriceAtTransaction: updatedWithSku.buyingPrice,
          reason: diff > 0 ? 'restock' : 'audit_adjustment',
          notes: `Stock adjustment from inventory management`
        });
      }

      localDB.logAction(session.userId, session.name, session.role, 'PRODUCT_UPDATE', `Updated product details for SKU ${updatedWithSku.sku}`);
    }
  },

  restockProduct: (productId: string, qty: number, buyingPrice?: number, newExpirationDate?: string | null, createNewBatch?: boolean) => {
    const products = localDB.getProducts();
    const p = products.find(prod => prod.id === productId);
    if (p) {
      const session = localDB.getSession();
      
      if (createNewBatch && newExpirationDate && p.expirationDate !== newExpirationDate) {
        // Create a new product as a new batch!
        // We'll generate a sub-SKU or add a suffix like "-B2" or a timestamp-based SKU so it remains unique.
        const cleanSku = p.sku.split('-B')[0]; // clean up any existing batch suffix
        const otherBatchesCount = products.filter(prod => prod.sku.startsWith(cleanSku)).length;
        const newSku = `${cleanSku}-B${otherBatchesCount + 1}`;
        const newName = `${p.name} (Batch ${otherBatchesCount + 1})`;
        
        const newProduct: Product = {
          id: 'P' + Math.floor(100 + Math.random() * 900).toString() + Math.floor(10 + Math.random() * 90).toString(),
          name: newName,
          sku: newSku,
          category: p.category,
          buyingPrice: buyingPrice !== undefined ? buyingPrice : p.buyingPrice,
          sellingPrice: p.sellingPrice,
          currentStock: qty,
          minStockLevel: p.minStockLevel,
          expirationDate: newExpirationDate,
          createdAt: new Date().toISOString()
        };
        products.push(newProduct);
        localDB.setProducts(products);

        localDB.logAction(session.userId, session.name, session.role, 'PRODUCT_CREATE', `Created separate batch for: ${newProduct.name} with different expiry: ${newExpirationDate}`);
        
        localDB.addTransaction({
          productId: newProduct.id,
          productName: newProduct.name,
          quantity: qty,
          type: 'in',
          buyingPriceAtTransaction: newProduct.buyingPrice,
          reason: 'restock',
          notes: `Batch restock with different expiry ${newExpirationDate}`
        });
        return { type: 'new_batch', product: newProduct };
      }

      // Default: Update/Overwrite or keep the same
      const originalStock = p.currentStock;
      p.currentStock += qty;
      if (buyingPrice !== undefined) {
        p.buyingPrice = buyingPrice;
      }
      if (newExpirationDate !== undefined) {
        p.expirationDate = newExpirationDate;
      }
      localDB.setProducts(products);

      localDB.logAction(session.userId, session.name, session.role, 'STOCK_IN', `Restocked ${qty} units of ${p.name}. Stock updated: ${originalStock} -> ${p.currentStock}`);
      
      localDB.addTransaction({
        productId: p.id,
        productName: p.name,
        quantity: qty,
        type: 'in',
        buyingPriceAtTransaction: buyingPrice !== undefined ? buyingPrice : p.buyingPrice,
        reason: 'restock',
        notes: `Manual stock-in replenishment`
      });
      return { type: 'merged', product: p };
    }
    return null;
  },

  addSale: (saleData: Omit<Sale, 'id' | 'timestamp' | 'synced'>): Sale => {
    const sales = localDB.getSales();
    const products = localDB.getProducts();
    const session = localDB.getSession();

    const newSale: Sale = {
      ...saleData,
      id: 'TX-' + new Date().toISOString().slice(0, 10).replace(/-/g, '') + '-' + Math.floor(100 + Math.random() * 900),
      timestamp: new Date().toISOString(),
      synced: false
    };

    // Deduct stock levels for items
    newSale.items.forEach(item => {
      const p = products.find(prod => prod.id === item.productId);
      if (p) {
        p.currentStock = Math.max(0, p.currentStock - item.quantity);
        
        // Add stock transaction for sale outflow
        localDB.addTransaction({
          productId: p.id,
          productName: p.name,
          quantity: -item.quantity,
          type: 'out',
          buyingPriceAtTransaction: item.buyingPrice,
          reason: 'sale',
          notes: `POS Transaction ${newSale.id}`
        });
      }
    });

    localDB.setProducts(products);
    sales.push(newSale);
    localDB.setSales(sales);

    localDB.logAction(session.userId, session.name, session.role, 'SALE', `Completed POS sale ${newSale.id}. Total: shs ${newSale.totalAmount.toLocaleString()}`);

    // If online, attempt background sync silently
    if (!localDB.isOfflineMode()) {
      localDB.triggerSync().catch(err => console.log('Background sync deferred: ', err.message));
    }

    return newSale;
  },

  addTransaction: (tx: Omit<StockTransaction, 'id' | 'timestamp' | 'operatorId' | 'operatorName'>) => {
    const txs = localDB.getTransactions();
    const session = localDB.getSession();
    const newTx: StockTransaction = {
      ...tx,
      id: generateId(),
      timestamp: new Date().toISOString(),
      operatorId: session.userId,
      operatorName: session.name
    };
    txs.push(newTx);
    localDB.setTransactions(txs);
  },

  logAction: (userId: string, userName: string, userRole: 'top_manager' | 'manager' | 'worker', actionType: string, details: string) => {
    localDB.init();
    const logs = cache[KEYS.AUDIT_LOGS] || [];
    const newLog: AuditLog = {
      id: generateId(),
      timestamp: new Date().toISOString(),
      userId,
      userName,
      userRole,
      actionType,
      details
    };
    logs.unshift(newLog); // newer first
    const sliced = logs.slice(0, 1000);
    cache[KEYS.AUDIT_LOGS] = sliced;
    localStorage.setItem(KEYS.AUDIT_LOGS, JSON.stringify(sliced)); // Cap logs at 1000
  },

  // Synchronization with Express Backend Server
  triggerSync: async (): Promise<{ success: boolean, syncedCount: number }> => {
    if (localDB.isOfflineMode()) {
      throw new Error("Cannot sync while in Offline Mode");
    }

    const session = localDB.getSession();
    const sales = localDB.getSales();
    const products = localDB.getProducts();
    const transactions = localDB.getTransactions();
    const auditLogs = localDB.getAuditLogs();
    const reports = localDB.getReports();
    const loans = localDB.getLoans();
    const expenses = localDB.getExpenses();

    const unsyncedSales = sales.filter(s => !s.synced);

    const payload = {
      sales: unsyncedSales,
      products,
      stockTransactions: transactions,
      auditLogs,
      reports,
      loans,
      expenses,
      role: session.role,
      userId: session.userId,
      hasLocalEdits: session.role === 'manager' // Managers can update inventory details
    };

    try {
      const response = await fetch('/api/sync', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        throw new Error(`Server returned status ${response.status}`);
      }

      const data = await response.json();

      if (data.success) {
        // Double-sided sync: overwrite local storage with master server lists
        if (data.sales) {
          // Keep synced status marked as true for all of them
          const resolvedSales = data.sales.map((s: any) => ({ ...s, synced: true }));
          localDB.setSales(resolvedSales);
        }
        if (data.products) {
          localDB.setProducts(data.products);
        }
        if (data.stockTransactions) {
          localDB.setTransactions(data.stockTransactions);
        }
        if (data.auditLogs) {
          localStorage.setItem(KEYS.AUDIT_LOGS, JSON.stringify(data.auditLogs));
        }
        if (data.reports) {
          localDB.setReports(data.reports);
        }
        if (data.loans) {
          localDB.setLoans(data.loans);
        }
        if (data.expenses) {
          localDB.setExpenses(data.expenses);
        }
        if (data.staff) {
          localDB.setStaffProfilesLocal(data.staff);
        }
        // Drop records deleted on other devices (tombstones). Must run after the
        // list overwrites above so nothing a stale merge kept survives.
        if (data.deletions) {
          const d = data.deletions;
          const drop = (ids: string[] | undefined, getter: () => any[], setter: (v: any[]) => void, key = 'id') => {
            if (!ids || ids.length === 0) return;
            const set = new Set(ids);
            const filtered = getter().filter((r: any) => !set.has(r[key]));
            setter(filtered);
          };
          drop(d.products, localDB.getProducts, localDB.setProducts);
          drop(d.sales, localDB.getSales, localDB.setSales);
          drop(d.loans, localDB.getLoans, localDB.setLoans);
          drop(d.expenses, localDB.getExpenses, localDB.setExpenses);
        }

        if (unsyncedSales.length > 0) {
          localDB.logAction(session.userId, session.name, session.role, 'SYNC', `Successfully synchronized ${unsyncedSales.length} POS sales to cloud backup`);
        }
      }

      return { success: true, syncedCount: unsyncedSales.length };
    } catch (err) {
      console.error("Sync error: ", err);
      throw err;
    }
  }
};
export default localDB;
