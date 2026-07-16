import express from 'express';
import { GoogleGenAI, Type } from '@google/genai';
import dotenv from 'dotenv';
import { ensureSchema, loadStore, saveStore, deleteRow, tombstone, untombstone, getDeletedIds, upsertRows } from './db.js';

dotenv.config();

const app = express();
const PORT = 3000;

app.use(express.json({ limit: '15mb' }));

// Initialize Gemini API client safely (with fallback if key is missing)
let ai: GoogleGenAI | null = null;
const apiKey = process.env.GEMINI_API_KEY;

if (apiKey) {
  try {
    ai = new GoogleGenAI({
      apiKey: apiKey,
      httpOptions: {
        headers: {
          'User-Agent': 'aistudio-build',
        }
      }
    });
  } catch (err) {
    console.error("Failed to initialize Gemini Client: ", err);
  }
} else {
  console.warn("GEMINI_API_KEY environment variable is not defined. AI reports will run on mock analyzer.");
}

// Ensure the Neon schema exists (and the single owner is seeded) before serving
// any request. Cached after the first call, so this is effectively free.
app.use(async (_req, res, next) => {
  try {
    await ensureSchema();
    next();
  } catch (err) {
    console.error('Schema initialization failed: ', err);
    res.status(500).json({ success: false, error: 'Database unavailable', message: (err as Error).message });
  }
});

// --- API ROUTES ---

// 1. Health check
app.get('/api/health', async (_req, res) => {
  try {
    const store = await loadStore();
    res.json({
      status: 'ok',
      time: new Date().toISOString(),
      hasAi: !!ai,
      db: 'neon',
      counts: {
        products: store.products.length,
        sales: store.sales.length,
        staff: store.staff.length,
      },
    });
  } catch (err) {
    res.status(500).json({ status: 'error', message: (err as Error).message });
  }
});

// 1.5 Staff directory (cloud-authoritative). Login flows pull this so a device
// with a stale locally-cached PIN still authenticates against Neon.
app.get('/api/staff', async (_req, res) => {
  try {
    const store = await loadStore();
    res.json({ success: true, staff: store.staff });
  } catch (err) {
    res.status(500).json({ success: false, message: (err as Error).message });
  }
});

// 2. Synchronization Endpoint (Two-way, merges state, adjusts stock levels)
app.post('/api/sync', async (req, res) => {
  const {
    sales = [],
    products = [],
    stockTransactions = [],
    auditLogs = [],
    reports = [],
    loans = [],
    expenses = [],
    staff = [],
    categories = [],
    expenseCategories = [],
    dirtyProductIds,
    dirtyLoanIds,
    role,
    hasLocalEdits = false,
  } = req.body;

  // Reject legacy demo/seed data that lingering old installs still re-push.
  // Real products created in-app get ids P100–P999 (and batch ids are longer),
  // so P001–P010 (regex ^P0\d\d$) is exclusively the removed demo seed. Demo
  // sales/transactions reference those product ids; demo audit logs came from
  // the removed demo staff (M001/W001/W002).
  const isDemoProductId = (id: string) => /^P0\d\d$/.test(id || '');
  // A product is legacy demo/test data if it has a demo seed id, or is the
  // known test artifact (sku REAL-1) used while wiring up the cloud database.
  const isDemoProduct = (p: any) =>
    isDemoProductId(p?.id) || p?.sku === 'REAL-1';
  const DEMO_USER_IDS = new Set(['M001', 'W001', 'W002']);
  const cleanProducts = (products as any[]).filter((p) => !isDemoProduct(p));
  const cleanStockTx = (stockTransactions as any[]).filter((t) => !isDemoProductId(t?.productId));
  const cleanAuditLogs = (auditLogs as any[]).filter((l) => !DEMO_USER_IDS.has(l?.userId));
  const cleanSales = (sales as any[]).filter(
    (s) => !((s?.items || []) as any[]).some((it) => isDemoProductId(it?.productId))
  );

  try {
    const store = await loadStore();

    // Tombstones: ids deliberately deleted on the server. A device still holding
    // any of these would otherwise re-push them here and resurrect them. We skip
    // re-inserting them, so the authoritative response (which omits them) makes
    // the delete propagate to that device's local storage on this same pull.
    const [
      deletedSales,
      deletedProducts,
      deletedLoans,
      deletedExpenses,
      deletedCategories,
      deletedExpenseCategories,
    ] = await Promise.all([
      getDeletedIds('sales'),
      getDeletedIds('products'),
      getDeletedIds('loans'),
      getDeletedIds('expenses'),
      getDeletedIds('categories'),
      getDeletedIds('expenseCategories'),
    ]);

    // A. Merge incoming sales and deduct stock for sales the server hasn't seen.
    cleanSales.forEach((incomingSale: any) => {
      if (deletedSales.has(incomingSale.id)) return;
      const exists = store.sales.some(s => s.id === incomingSale.id);
      if (!exists) {
        store.sales.push({ ...incomingSale, synced: true });

        // Decrement product stock levels for items in this newly-seen sale.
        (incomingSale.items || []).forEach((item: any) => {
          const match = store.products.find(p => p.id === item.productId);
          if (match) {
            match.currentStock = Math.max(0, match.currentStock - item.quantity);
          }
        });
      }
    });

    // B. Merge incoming products if a manager made modifications. A product that
    // has been deleted (tombstoned) is never re-added, even if a stale device
    // still has it in its pushed catalog.
    const pushableProducts = cleanProducts.filter((p: any) => !deletedProducts.has(p?.id));
    // Ids whose stock level this request has taken from the client verbatim. The
    // client already folded its restocks and adjustments into the currentStock it
    // pushed, so step C must not add those quantities on again (that double-counted
    // every restock: 100 + a 10 restock landed at 120).
    const authoritativeStockIds = new Set<string>();
    // Ids this device actually edited since its last successful sync. Every device
    // pushes its FULL catalog, but most of those rows are just a copy of what it
    // last pulled — taking them as authoritative let an idle terminal silently
    // revert a restock made on another machine (last writer wins).
    //
    // A client that does not send this list gets NO authority over rows the cloud
    // already knows. It used to get whole-catalog authority for backwards compat,
    // and that was actively destroying inventory: a stale client (an old APK, or a
    // browser tab holding a cached bundle) re-pushed its old catalog every poll and
    // reverted every edit made anywhere else within seconds. Because it then
    // adopted its own value back from the response, it never self-corrected — it
    // just kept winning. carrot seeds lost 250 units this way on 2026-07-15.
    //
    // Failing closed is safe: such a client can still create products the cloud has
    // never seen, its sales still merge, and its restocks still land through the
    // stock-transaction ledger in step C (which applies quantities for exactly the
    // products this request did not claim authority over).
    const dirtySet: Set<string> | null = Array.isArray(dirtyProductIds)
      ? new Set((dirtyProductIds as any[]).map(String))
      : null;
    if (pushableProducts.length > 0 && (role === 'manager' || role === 'top_manager' || hasLocalEdits)) {
      pushableProducts.forEach((clientProd: any) => {
        const sIdx = store.products.findIndex(p => p.id === clientProd.id);
        if (sIdx === -1) {
          // The cloud has never seen this product — always take it, so a catalog
          // that predates cloud sync still backfills.
          store.products.push(clientProd);
          authoritativeStockIds.add(clientProd.id);
        } else if (dirtySet && dirtySet.has(String(clientProd.id))) {
          store.products[sIdx] = { ...store.products[sIdx], ...clientProd };
          authoritativeStockIds.add(clientProd.id);
        }
        // Otherwise: known to the cloud and not declared as changed here — leave
        // the cloud's copy alone and let this device adopt it from the response.
      });
    } else if (store.products.length === 0 && pushableProducts.length > 0) {
      // First device to bring a catalog online seeds the empty server catalog.
      store.products.push(...pushableProducts);
      pushableProducts.forEach((p: any) => authoritativeStockIds.add(p.id));
    }

    // C. Append stock transactions. The quantity is only applied for products this
    // request did NOT carry an authoritative stock level for — otherwise the tx is
    // recorded for the ledger only, since the pushed product already reflects it.
    cleanStockTx.forEach((incomingTx: any) => {
      const exists = store.stockTransactions.some(t => t.id === incomingTx.id);
      if (!exists) {
        store.stockTransactions.push(incomingTx);
        if (incomingTx.reason !== 'sale' && !authoritativeStockIds.has(incomingTx.productId)) {
          const prod = store.products.find(p => p.id === incomingTx.productId);
          if (prod) {
            prod.currentStock = Math.max(0, prod.currentStock + incomingTx.quantity);
          }
        }
      }
    });

    // D. Append audit logs.
    cleanAuditLogs.forEach((incomingLog: any) => {
      if (!store.auditLogs.some(l => l.id === incomingLog.id)) {
        store.auditLogs.push(incomingLog);
      }
    });

    // E. Append EOD reports.
    reports.forEach((incomingReport: any) => {
      if (!store.reports.some(r => r.id === incomingReport.id)) {
        store.reports.push(incomingReport);
      }
    });

    // F. Merge loans (upsert by id — balances/payments change over time).
    // Skip any loan that has been deleted so a stale device can't resurrect it.
    // Only loans this device actually changed are authoritative — same reasoning
    // as products above, and a client that declares nothing gets no authority over
    // loans the cloud already knows. An idle terminal pushing its pre-payment copy
    // of a loan would otherwise wipe out a repayment recorded on another machine —
    // money the business is owed, silently forgiven.
    const dirtyLoanSet: Set<string> | null = Array.isArray(dirtyLoanIds)
      ? new Set((dirtyLoanIds as any[]).map(String))
      : null;
    loans.forEach((incomingLoan: any) => {
      if (deletedLoans.has(incomingLoan.id)) return;
      const idx = store.loans.findIndex(l => l.id === incomingLoan.id);
      if (idx === -1) {
        store.loans.push(incomingLoan);
      } else if (dirtyLoanSet && dirtyLoanSet.has(String(incomingLoan.id))) {
        store.loans[idx] = incomingLoan;
      }
    });

    // G. Merge expenses (append by id). Skip tombstoned expenses.
    expenses.forEach((incomingExp: any) => {
      if (deletedExpenses.has(incomingExp.id)) return;
      if (!store.expenses.some(e => e.id === incomingExp.id)) {
        store.expenses.push(incomingExp);
      }
    });

    // G2. Merge category lists (union). Categories are a shared, user-managed set
    // rather than records with ids, so every device contributes the names it knows
    // and the cloud holds the union. A name that was explicitly deleted is
    // tombstoned and skipped, otherwise the next device to sync its stale list
    // would resurrect it. Re-adding a deleted name goes through
    // /api/categories/add, which clears the tombstone first.
    const mergeNames = (incoming: any[], current: string[], deleted: Set<string>) => {
      const merged = [...current];
      (incoming as any[]).forEach((raw) => {
        const name = typeof raw === 'string' ? raw.trim() : '';
        if (!name || deleted.has(name) || merged.includes(name)) return;
        merged.push(name);
      });
      return merged;
    };
    store.categories = mergeNames(categories, store.categories, deletedCategories);
    store.expenseCategories = mergeNames(
      expenseCategories,
      store.expenseCategories,
      deletedExpenseCategories
    );

    // H. Staff is STRICTLY server-authoritative — the sync endpoint ignores any
    // staff a client sends (`staff` in the payload is intentionally unused). This
    // prevents a device holding stale/demo accounts from polluting or clobbering
    // the cloud directory. Staff changes go only through /api/staff/save and
    // /api/staff/delete; sync merely returns the master list below.
    void staff;

    // Sort audit logs newest-first for the response.
    store.auditLogs.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());

    await saveStore(store);

    res.json({
      success: true,
      message: 'Synchronization completed successfully',
      sales: store.sales,
      products: store.products,
      stockTransactions: store.stockTransactions,
      auditLogs: store.auditLogs,
      reports: store.reports,
      loans: store.loans,
      expenses: store.expenses,
      staff: store.staff,
      categories: store.categories,
      expenseCategories: store.expenseCategories,
      // Tombstoned ids so clients can drop deleted records their local merge
      // would otherwise keep (loans merge preserves local-only entries, so a
      // delete on another device wouldn't propagate without this).
      deletions: {
        sales: [...deletedSales],
        products: [...deletedProducts],
        loans: [...deletedLoans],
        expenses: [...deletedExpenses],
        categories: [...deletedCategories],
        expenseCategories: [...deletedExpenseCategories],
      },
    });
  } catch (error) {
    console.error("Sync failed: ", error);
    res.status(500).json({ success: false, error: 'Database error', message: (error as Error).message });
  }
});

// 2.4 Authoritative staff upsert (deliberate add / promote / PIN change).
// Managerial roles only. This is how an existing staff row is legitimately
// changed on the server (the sync endpoint is add-only for staff).
app.post('/api/staff/save', async (req, res) => {
  const { staff: profile, role } = req.body;
  if (role !== 'manager' && role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only managers can modify staff.' });
  }
  if (!profile || !profile.userId) {
    return res.status(400).json({ success: false, message: 'A staff profile with a userId is required.' });
  }
  try {
    const store = await loadStore();
    const idx = store.staff.findIndex(s => s.userId === profile.userId);
    if (idx !== -1) store.staff[idx] = profile;
    else store.staff.push(profile);
    await saveStore({ staff: store.staff });
    res.json({ success: true, staff: store.staff });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 2.45 Authoritative staff delete. Managerial roles only.
app.post('/api/staff/delete', async (req, res) => {
  const { userId, role } = req.body;
  if (role !== 'manager' && role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only managers can remove staff.' });
  }
  try {
    await deleteRow('staff', userId);
    const store = await loadStore();
    res.json({ success: true, staff: store.staff });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 2.48 Authoritative product delete. Top Manager only. The bulk /api/sync
// endpoint only ever upserts products (it never removes rows), so a catalog
// deletion has to go through this dedicated route or the product would be
// resurrected on the next pull.
app.post('/api/products/delete', async (req, res) => {
  const { productId, role } = req.body;
  if (role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only the Top Manager can delete commodities.' });
  }
  if (!productId) {
    return res.status(400).json({ success: false, message: 'A productId is required.' });
  }
  try {
    await deleteRow('products', productId);
    await tombstone('products', productId);
    const store = await loadStore();
    res.json({ success: true, products: store.products });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 2.49 Authoritative loan delete. Top Manager only. Same rationale as the
// product delete: /api/sync only upserts loans, so a deletion must be explicit.
app.post('/api/loans/delete', async (req, res) => {
  const { loanId, role } = req.body;
  if (role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only the Top Manager can delete loans.' });
  }
  if (!loanId) {
    return res.status(400).json({ success: false, message: 'A loanId is required.' });
  }
  try {
    await deleteRow('loans', loanId);
    await tombstone('loans', loanId);
    const store = await loadStore();
    res.json({ success: true, loans: store.loans });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 2.491 Authoritative expense delete. Top Manager only.
app.post('/api/expenses/delete', async (req, res) => {
  const { expenseId, role } = req.body;
  if (role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only the Top Manager can delete expenses.' });
  }
  if (!expenseId) {
    return res.status(400).json({ success: false, message: 'An expenseId is required.' });
  }
  try {
    await deleteRow('expenses', expenseId);
    await tombstone('expenses', expenseId);
    const store = await loadStore();
    res.json({ success: true, expenses: store.expenses });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 2.4 Category routes. Categories are a shared list, so an add/delete has to be
// authoritative rather than ride along on the next bulk sync — otherwise the
// change is invisible to every other terminal. `kind` picks the product catalog
// list or the expenditure list.
const categoryTarget = (kind: any) =>
  kind === 'expense'
    ? { table: 'expense_categories' as const, collection: 'expenseCategories' }
    : { table: 'categories' as const, collection: 'categories' };

app.post('/api/categories/add', async (req, res) => {
  const { name, kind, role } = req.body;
  if (role !== 'manager' && role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only managers can add categories.' });
  }
  const clean = typeof name === 'string' ? name.trim() : '';
  if (!clean) {
    return res.status(400).json({ success: false, message: 'A category name is required.' });
  }
  try {
    const { table, collection } = categoryTarget(kind);
    // Clear any tombstone first, so a category that was deleted earlier can be
    // deliberately brought back. Without this the add would be silently ignored.
    await untombstone(collection, clean);
    await upsertRows(table, [{ name: clean }], 'name');
    const store = await loadStore();
    res.json({
      success: true,
      categories: store.categories,
      expenseCategories: store.expenseCategories,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

app.post('/api/categories/delete', async (req, res) => {
  const { name, kind, role } = req.body;
  if (role !== 'manager' && role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Only managers can delete categories.' });
  }
  const clean = typeof name === 'string' ? name.trim() : '';
  if (!clean) {
    return res.status(400).json({ success: false, message: 'A category name is required.' });
  }
  try {
    const { table, collection } = categoryTarget(kind);
    await deleteRow(table, clean);
    await tombstone(collection, clean);
    const store = await loadStore();
    res.json({
      success: true,
      categories: store.categories,
      expenseCategories: store.expenseCategories,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 2.5 Manager void/delete transaction route
app.post('/api/sales/delete', async (req, res) => {
  const { saleId, role, userId, userName } = req.body;

  if (role !== 'manager' && role !== 'top_manager') {
    return res.status(403).json({ success: false, message: 'Forbidden. Only managers can void transactions.' });
  }

  try {
    const store = await loadStore();
    const saleIndex = store.sales.findIndex(s => s.id === saleId);
    if (saleIndex === -1) {
      return res.status(404).json({ success: false, message: 'Transaction not found.' });
    }

    const voidedSale = store.sales[saleIndex];

    // Replenish product stock for the voided items.
    (voidedSale.items || []).forEach((item: any) => {
      const prod = store.products.find(p => p.id === item.productId);
      if (prod) {
        prod.currentStock += item.quantity;
      }
    });

    // Remove the sale from history (and from Neon).
    store.sales.splice(saleIndex, 1);

    const voidTx = {
      id: 'TX-VOID-' + Math.random().toString(36).substring(2, 9).toUpperCase(),
      productId: '',
      productName: `VOID POS ${saleId}`,
      quantity: 0,
      type: 'in',
      buyingPriceAtTransaction: 0,
      timestamp: new Date().toISOString(),
      operatorId: userId,
      operatorName: userName,
      reason: 'audit_adjustment',
      notes: `Voided completed sale ${saleId}. Stock replenished.`
    };
    store.stockTransactions.push(voidTx);

    store.auditLogs.unshift({
      id: 'LOG-' + Math.random().toString(36).substring(2, 9).toUpperCase(),
      timestamp: new Date().toISOString(),
      userId,
      userName,
      userRole: role,
      actionType: 'SALE_VOID',
      details: `Voided POS Transaction ${saleId} (Amount: shs ${voidedSale.totalAmount.toLocaleString()}). Returned items to stock.`
    });

    await deleteRow('sales', saleId);
    await tombstone('sales', saleId);
    await saveStore(store);

    res.json({
      success: true,
      message: 'Transaction voided and stock replenished successfully',
      sales: store.sales,
      products: store.products,
      stockTransactions: store.stockTransactions,
      auditLogs: store.auditLogs
    });
  } catch (error) {
    console.error("Void transaction failed: ", error);
    res.status(500).json({ success: false, message: (error as Error).message });
  }
});

// 3. EOD balancing and Gemini financial reports
app.post('/api/gemini/analyze', async (req, res) => {
  const { sales = [], products = [], date, currency = 'shs', ownerContact = 'Business Owner' } = req.body;

  // Compute standard summary stats
  const totalSalesVal = sales.reduce((acc: number, s: any) => acc + s.totalAmount, 0);
  const totalProfitVal = sales.reduce((acc: number, s: any) => acc + s.totalProfit, 0);
  const totalStakedVal = sales.reduce((acc: number, s: any) => acc + s.totalBuyingPrice, 0);
  const salesCount = sales.length;

  const lowStockProducts = products.filter((p: any) => p.currentStock <= p.minStockLevel);
  const expiringProducts = products.filter((p: any) => {
    if (!p.expirationDate) return false;
    const exp = new Date(p.expirationDate);
    const today = new Date();
    const diffTime = exp.getTime() - today.getTime();
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return diffDays >= 0 && diffDays <= 7;
  });

  // Fallback response generator in case AI is disabled
  const generateFallback = () => {
    return {
      eodSummaryText: `Business operations on ${date} balanced successfully. The total revenue collected stood at ${currency} ${totalSalesVal.toLocaleString()}, with an inventory investment (staked capital) of ${currency} ${totalStakedVal.toLocaleString()}. This yielded a net profitability of ${currency} ${totalProfitVal.toLocaleString()}. A total of ${salesCount} transactions were registered.`,
      ownerMessageDraft: `🛒 SUPERMARKET EOD REPORT - ${date}\n------------------------\nTotal Sales: ${currency} ${totalSalesVal.toLocaleString()}\nTotal Staked: ${currency} ${totalStakedVal.toLocaleString()}\nNet Profit: ${currency} ${totalProfitVal.toLocaleString()}\nNo. of Sales: ${salesCount}\n\n⚠️ Low Stock Alerts: ${lowStockProducts.length} items.\n🗓️ Expiring Soon: ${expiringProducts.length} items.\n\nBalanced and backed up securely.`,
      strategicAdvice: [
        `Inventory Capitalization: A total of ${currency} ${totalStakedVal.toLocaleString()} was staked (buying cost). Ensure markup percentages remain aligned with market rates.`,
        `Low Stock Warnings: ${lowStockProducts.length > 0 ? `${lowStockProducts.map((p: any) => p.name).slice(0, 3).join(', ')} require replenishment.` : 'All core commodities have healthy stock levels.'}`,
        `Waste Mitigation: Watch out for ${expiringProducts.length} items near expiration to avoid financial losses due to spoilage.`
      ],
      restockAlerts: lowStockProducts.map((p: any) => `${p.name} (SKU: ${p.sku}) - Current: ${p.currentStock} units left (Min threshold: ${p.minStockLevel})`)
    };
  };

  if (!ai) {
    return res.json({
      success: true,
      report: generateFallback(),
      method: 'rule-based-fallback'
    });
  }

  try {
    const productsSummary = products.map((p: any) => `${p.name} (Stock: ${p.currentStock}, Category: ${p.category}, Expiry: ${p.expirationDate || 'N/A'})`).join('\n');
    const salesSummary = sales.map((s: any) => `TX: ${s.id}, Amt: ${s.totalAmount}, Profit: ${s.totalProfit}, Items: ${s.items.map((it: any) => `${it.productName} (x${it.quantity})`).join(', ')}`).join('\n');

    const prompt = `
You are the Chief Financial Intelligence Agent for a major retail supermarket. Your role is to balance the books at the end of the day (${date}) and draft a scannable executive update for the business owner (${ownerContact}).

Here is the financial data collected for ${date}:
- Total Sales Transactions: ${salesCount}
- Gross Sales Revenue: ${currency} ${totalSalesVal}
- Staked Capital (Cost of Inventory Sold): ${currency} ${totalStakedVal}
- Net Profit Made: ${currency} ${totalProfitVal}
- Currency: ${currency}

Current inventory snapshot:
${productsSummary}

Sales Transactions logged today:
${salesSummary}

Generate a structured financial report and return it strictly in the JSON schema requested.
The response must include:
1. eodSummaryText: A professional executive summary evaluating the margins, revenue performance, and capital efficiency. Keep it encouraging but realistic.
2. ownerMessageDraft: An elegant, highly professional SMS/Email text draft to be sent to the business owner summarizing total sales, staked cost, net profit, transaction count, and alert summaries. Make it clean and mobile-friendly.
3. strategicAdvice: At least 3 detailed bullet points of actionable strategic advice based on today's sales velocity and stock status.
4. restockAlerts: List of alerts for low-stock items or items near expiration.
`;

    const response = await ai.models.generateContent({
      model: 'gemini-3.5-flash',
      contents: prompt,
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            eodSummaryText: {
              type: Type.STRING,
              description: 'A professional executive text report explaining the business metrics'
            },
            ownerMessageDraft: {
              type: Type.STRING,
              description: 'An elegant SMS or Email text summary to notify the business owner'
            },
            strategicAdvice: {
              type: Type.ARRAY,
              items: { type: Type.STRING },
              description: 'Actionable financial and inventory management advice bullets'
            },
            restockAlerts: {
              type: Type.ARRAY,
              items: { type: Type.STRING },
              description: 'Warning strings for items under stocked or expiring'
            }
          },
          required: ['eodSummaryText', 'ownerMessageDraft', 'strategicAdvice', 'restockAlerts']
        }
      }
    });

    const reportJson = JSON.parse(response.text || '{}');
    res.json({
      success: true,
      report: reportJson,
      method: 'gemini-ai-engine'
    });
  } catch (error) {
    console.error("Gemini analytical generation failed: ", error);
    res.json({
      success: true,
      report: generateFallback(),
      method: 'rule-based-fallback-on-error',
      error: (error as Error).message
    });
  }
});

// The Express app only defines the /api/* routes. It is consumed in two ways:
//   - Local dev / self-hosted: dev-server.ts imports it, attaches Vite (or static
//     dist serving) and opens a listener.
//   - Vercel: api/[...path].ts imports it directly as a serverless function handler.
// Keeping the client/static/Vite bootstrap out of this file ensures the serverless
// bundle never pulls in Vite (a heavy dev-only dependency).
export { PORT };
export default app;
