import React, { useState, useMemo } from 'react';
import { Product, Sale, EndOfDayReport, Loan } from '../types';
import localDB from '../utils/localDB';

// Cash-basis: profit recognized on a sale is proportional to the cash actually
// collected (the credit/loan portion's profit is deferred to repayment).
const recognizedProfit = (s: Sale): number =>
  s.totalAmount > 0 ? s.totalProfit * ((s.amountPaid || 0) / s.totalAmount) : s.totalProfit;
import { 
  TrendingUp, PiggyBank, DollarSign, RefreshCw, AlertTriangle, 
  Sparkles, Calendar, Mail, CheckCircle2, ChevronRight, Package 
} from 'lucide-react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts';
import { motion, AnimatePresence } from 'motion/react';

interface DashboardViewProps {
  onRefresh: () => void;
}

export const DashboardView: React.FC<DashboardViewProps> = ({ onRefresh }) => {
  const [products, setProducts] = useState<Product[]>(() => localDB.getProducts());
  const [sales, setSales] = useState<Sale[]>(() => localDB.getSales());
  const [loans, setLoans] = useState<Loan[]>(() => localDB.getLoans());
  const [reports, setReports] = useState<EndOfDayReport[]>(() => localDB.getReports());
  const [selectedPeriod, setSelectedPeriod] = useState<'today' | 'yesterday' | 'weekly' | 'monthly' | 'yearly' | 'all'>('all');
  const [isBalancing, setIsBalancing] = useState(false);
  const [activeEodReport, setActiveEodReport] = useState<EndOfDayReport | null>(null);
  const [showNotificationModal, setShowNotificationModal] = useState(false);
  const [isSendingNotification, setIsSendingNotification] = useState(false);
  const [ownerContact, setOwnerContact] = useState('+256 702 345 678');

  const handleRefresh = () => {
    setProducts(localDB.getProducts());
    setSales(localDB.getSales());
    setLoans(localDB.getLoans());
    setReports(localDB.getReports());
    onRefresh();
  };

  // Shared period predicate — used for both sales and loan repayments so both
  // sides of the cash-basis figures use one definition of the window.
  const inPeriod = React.useCallback((timestamp: string): boolean => {
    const todayStr = '2026-07-02';
    const yesterdayStr = '2026-07-01';
    const anchorDate = new Date('2026-07-02T23:59:59Z');
    const dateStr = timestamp.split('T')[0];
    if (selectedPeriod === 'today') return dateStr === todayStr;
    if (selectedPeriod === 'yesterday') return dateStr === yesterdayStr;
    const dt = new Date(timestamp);
    const diffDays = (anchorDate.getTime() - dt.getTime()) / (1000 * 60 * 60 * 24);
    if (selectedPeriod === 'weekly') return diffDays >= 0 && diffDays <= 7;
    if (selectedPeriod === 'monthly') return diffDays >= 0 && diffDays <= 30;
    if (selectedPeriod === 'yearly') return dt.getUTCFullYear() === 2026;
    return true; // 'all'
  }, [selectedPeriod]);

  // 1. Filter sales by period
  const filteredSales = useMemo(
    () => sales.filter(s => inPeriod(s.timestamp)),
    [sales, inPeriod]
  );

  // Cash + profit realised from loan repayments received within the period.
  // Profit lands on the payment's own date (cash-basis), not the sale date.
  const loanCollections = useMemo(() => {
    let cash = 0;
    let profit = 0;
    loans.forEach(l => {
      (l.payments || []).forEach(p => {
        if (!inPeriod(p.timestamp)) return;
        cash += p.amount;
        profit += p.amount * (l.profitRate || 0);
      });
    });
    return { cash, profit };
  }, [loans, inPeriod]);

  // 2. Financial Metrics — CASH-BASIS. Revenue = cash paid on sales + loan
  // repayments collected. Profit = recognised (paid-portion) sale profit + the
  // profit realised from repayments.
  const metrics = useMemo(() => {
    let revenue = 0;
    let stakedCost = 0; // Cost of inventory sold
    let profit = 0;
    const transactionCount = filteredSales.length;

    filteredSales.forEach(s => {
      revenue += (s.amountPaid || 0);
      stakedCost += s.totalBuyingPrice;
      profit += recognizedProfit(s);
    });

    revenue += loanCollections.cash;
    profit += loanCollections.profit;

    return {
      revenue,
      stakedCost,
      profit,
      transactionCount
    };
  }, [filteredSales, loanCollections]);

  // 3. Alerts computations
  const alerts = useMemo(() => {
    const lowStock = products.filter(p => p.currentStock <= p.minStockLevel);
    
    const expiring = products.filter(p => {
      if (!p.expirationDate) return false;
      const exp = new Date(p.expirationDate);
      const today = new Date('2026-07-02');
      const diffTime = exp.getTime() - today.getTime();
      const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
      return diffDays >= 0 && diffDays <= 7;
    });

    return {
      lowStock,
      expiring
    };
  }, [products]);

  // 4. Data for charts
  const salesTrendData = useMemo(() => {
    // Group sales by date/hour
    const groups: { [key: string]: { revenue: number, profit: number } } = {};
    
    // Sort sales chronologically
    const sorted = [...sales].sort((a, b) => a.timestamp.localeCompare(b.timestamp));
    
    sorted.forEach(s => {
      // Format: YYYY-MM-DD or readable time
      const dateStr = s.timestamp.split('T')[0];
      const hour = new Date(s.timestamp).getUTCHours();
      const label = `${dateStr} ${hour}:00`;
      
      if (!groups[label]) {
        groups[label] = { revenue: 0, profit: 0 };
      }
      groups[label].revenue += (s.amountPaid || 0);
      groups[label].profit += recognizedProfit(s);
    });

    return Object.entries(groups).map(([label, val]) => ({
      name: label,
      Revenue: val.revenue,
      Profit: val.profit
    })).slice(-10); // Show last 10 hourly periods for visual balance
  }, [sales]);

  const categoryDistributionData = useMemo(() => {
    const cats: { [key: string]: number } = {};
    filteredSales.forEach(s => {
      s.items.forEach(it => {
        // Find category from product DB or item default
        const prod = products.find(p => p.id === it.productId);
        const category = prod ? prod.category : 'General';
        cats[category] = (cats[category] || 0) + it.totalSellingPrice;
      });
    });

    return Object.entries(cats).map(([name, value]) => ({ name, value }));
  }, [filteredSales, products]);

  const topCommodities = useMemo(() => {
    const counts: { [key: string]: { name: string, quantity: number, revenue: number, profit: number, category: string, sku: string } } = {};
    
    filteredSales.forEach(s => {
      // Cash-basis: count only the profit on the paid fraction of this sale.
      const paidFrac = s.totalAmount > 0 ? (s.amountPaid || 0) / s.totalAmount : 1;
      s.items.forEach(it => {
        const pId = it.productId;
        const prod = products.find(p => p.id === pId);
        const category = prod ? prod.category : 'General';
        const sku = prod ? prod.sku : '';

        if (!counts[pId]) {
          counts[pId] = {
            name: it.productName,
            quantity: 0,
            revenue: 0,
            profit: 0,
            category,
            sku
          };
        }
        counts[pId].quantity += it.quantity;
        counts[pId].revenue += it.totalSellingPrice;
        counts[pId].profit += it.profit * paidFrac;
      });
    });

    return Object.entries(counts)
      .map(([id, val]) => ({ id, ...val }))
      .sort((a, b) => b.quantity - a.quantity);
  }, [filteredSales, products]);

  const COLORS = ['#4f46e5', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#14b8a6'];

  // 5. Automatic EOD balancing and sending summary to business owner (Gemini-powered)
  const handleEodBalancing = async () => {
    setIsBalancing(true);
    setActiveEodReport(null);
    const todayStr = '2026-07-02';

    // Get today's sales
    const todaySales = sales.filter(s => s.timestamp.startsWith(todayStr));

    try {
      const response = await fetch('/api/gemini/analyze', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          sales: todaySales,
          products,
          date: todayStr,
          currency: 'shs',
          ownerContact: 'Business Owner'
        })
      });

      if (!response.ok) {
        throw new Error('EOD server analysis failed');
      }

      const data = await response.json();
      const aiReport = data.report;

      // Cash-basis EOD: cash collected today = cash paid on today's sales + loan
      // repayments received today; profit is recognised on the cash portion plus
      // profit realised from today's repayments.
      let loanCashToday = 0;
      let loanProfitToday = 0;
      localDB.getLoans().forEach(l => {
        (l.payments || []).forEach(p => {
          if (!p.timestamp.startsWith(todayStr)) return;
          loanCashToday += p.amount;
          loanProfitToday += p.amount * (l.profitRate || 0);
        });
      });
      const totalSalesVal = todaySales.reduce((acc, s) => acc + (s.amountPaid || 0), 0) + loanCashToday;
      const totalProfitVal = todaySales.reduce((acc, s) => acc + recognizedProfit(s), 0) + loanProfitToday;
      const totalStakedVal = todaySales.reduce((acc, s) => acc + s.totalBuyingPrice, 0);

      const newReport: EndOfDayReport = {
        id: 'EOD-' + todayStr.replace(/-/g, '') + '-' + Math.floor(100 + Math.random() * 900),
        date: todayStr,
        totalSales: totalSalesVal,
        totalProfit: totalProfitVal,
        totalStaked: totalStakedVal,
        salesCount: todaySales.length,
        reportDrawnBy: localDB.getSession().name,
        reportDrawnAt: new Date().toISOString(),
        ownerNotificationSent: false,
        ownerContact: ownerContact,
        aiInsights: JSON.stringify(aiReport)
      };

      // Store report in database
      const existingReports = localDB.getReports();
      localDB.setReports([newReport, ...existingReports]);
      
      const session = localDB.getSession();
      localDB.logAction(session.userId, session.name, session.role, 'EOD_BALANCE', `Generated automated EOD Balance Report for ${todayStr}. Total Sales: shs ${totalSalesVal.toLocaleString()}`);

      setActiveEodReport(newReport);
      handleRefresh();
    } catch (err) {
      console.error(err);
      alert("Error generating EOD balancing analysis");
    } finally {
      setIsBalancing(false);
    }
  };

  // Send automated report to owner
  const handleSendNotification = () => {
    setIsSendingNotification(true);
    setTimeout(() => {
      setIsSendingNotification(false);
      setShowNotificationModal(false);
      
      if (activeEodReport) {
        const updated = reports.map(r => {
          if (r.id === activeEodReport.id) {
            return { ...r, ownerNotificationSent: true };
          }
          return r;
        });
        localDB.setReports(updated);
        setActiveEodReport(prev => prev ? { ...prev, ownerNotificationSent: true } : null);
        
        const session = localDB.getSession();
        localDB.logAction(session.userId, session.name, session.role, 'EOD_BALANCE', `SMS daily ledger successfully dispatched to owner at ${ownerContact}`);
        handleRefresh();
      }
    }, 1500);
  };

  // Parse AI report parts safely
  const parsedAiInsights = useMemo(() => {
    if (!activeEodReport?.aiInsights) return null;
    try {
      return JSON.parse(activeEodReport.aiInsights);
    } catch (e) {
      return null;
    }
  }, [activeEodReport]);

  return (
    <div className="space-y-6">
      {/* Time Period Selector & EOD trigger */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-4 rounded-2xl border border-slate-100 shadow-sm">
        <div className="flex items-center gap-2">
          <span className="text-xs font-display font-semibold text-slate-400 uppercase tracking-wider">Metrics Scope:</span>
          <div className="flex bg-slate-50 border border-slate-200/50 p-1 rounded-xl flex-wrap gap-0.5">
            {(['today', 'yesterday', 'weekly', 'monthly', 'yearly', 'all'] as const).map(p => (
              <button
                key={p}
                onClick={() => setSelectedPeriod(p)}
                className={`px-3 py-1 rounded-lg text-xs font-display font-medium capitalize transition-all ${
                  selectedPeriod === p
                    ? 'bg-white text-slate-900 shadow-sm font-semibold'
                    : 'text-slate-500 hover:text-slate-800'
                }`}
              >
                {p === 'all' ? 'All-Time' : p}
              </button>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={handleRefresh}
            className="p-2 border border-slate-200 hover:bg-slate-50 text-slate-600 rounded-xl transition-all"
            title="Refresh statistics"
          >
            <RefreshCw size={16} />
          </button>
          
          <button
            onClick={handleEodBalancing}
            disabled={isBalancing}
            className="bg-slate-900 hover:bg-slate-800 disabled:bg-slate-300 text-white rounded-xl px-4 py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-sm hover:shadow flex items-center gap-2"
          >
            {isBalancing ? (
              <>
                <span className="animate-spin rounded-full h-3 w-3 border-b-2 border-white"></span>
                Balancing Ledger...
              </>
            ) : (
              <>
                <Sparkles size={14} className="text-amber-400" />
                Automatic EOD Balance
              </>
            )}
          </button>
        </div>
      </div>

      {/* Financial Metrics Row */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-5">
        {/* Gross Sales */}
        <div className="bg-white border border-slate-100 rounded-2xl p-5 shadow-sm relative overflow-hidden flex flex-col justify-between">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-display font-medium text-slate-400">Gross Sales Revenue</p>
              <h3 className="font-mono text-xl font-bold text-slate-950 mt-1">
                shs {metrics.revenue.toLocaleString()}
              </h3>
            </div>
            <div className="p-3 bg-indigo-50 text-indigo-600 rounded-xl">
              <TrendingUp size={20} />
            </div>
          </div>
          <p className="text-[10px] text-slate-400 mt-4 font-display">
            Gross income accumulated in period
          </p>
        </div>

        {/* Staked Capital */}
        <div className="bg-white border border-slate-100 rounded-2xl p-5 shadow-sm relative overflow-hidden flex flex-col justify-between">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-display font-medium text-slate-400">Staked Capital (Cost)</p>
              <h3 className="font-mono text-xl font-bold text-slate-950 mt-1">
                shs {metrics.stakedCost.toLocaleString()}
              </h3>
            </div>
            <div className="p-3 bg-amber-50 text-amber-600 rounded-xl">
              <PiggyBank size={20} />
            </div>
          </div>
          <p className="text-[10px] text-slate-400 mt-4 font-display">
            Investment locked in sold inventory
          </p>
        </div>

        {/* Net Profit */}
        <div className="bg-white border border-slate-100 rounded-2xl p-5 shadow-sm relative overflow-hidden flex flex-col justify-between">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-display font-medium text-slate-400">Net Profit / Loss</p>
              <h3 className={`font-mono text-xl font-bold mt-1 ${metrics.profit >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                shs {metrics.profit.toLocaleString()}
              </h3>
            </div>
            <div className={`p-3 rounded-xl ${metrics.profit >= 0 ? 'bg-emerald-50 text-emerald-600' : 'bg-red-50 text-red-500'}`}>
              <DollarSign size={20} />
            </div>
          </div>
          <p className="text-[10px] text-slate-400 mt-4 font-display">
            Markup value captured (Revenue &minus; Capital)
          </p>
        </div>

        {/* Transactions */}
        <div className="bg-white border border-slate-100 rounded-2xl p-5 shadow-sm relative overflow-hidden flex flex-col justify-between">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs font-display font-medium text-slate-400">Total Transactions</p>
              <h3 className="font-mono text-xl font-bold text-slate-950 mt-1">
                {metrics.transactionCount}
              </h3>
            </div>
            <div className="p-3 bg-purple-50 text-purple-600 rounded-xl">
              <Package size={20} />
            </div>
          </div>
          <p className="text-[10px] text-slate-400 mt-4 font-display">
            Distinct sales processes finalized
          </p>
        </div>
      </div>

      {/* Critical Warnings Panel (Low stock & Expirations) */}
      {(alerts.lowStock.length > 0 || alerts.expiring.length > 0) && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
          {/* Low Stock Warns */}
          {alerts.lowStock.length > 0 && (
            <div className="bg-amber-50/40 border border-amber-100 rounded-2xl p-5 shadow-sm flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-2 text-amber-800 mb-3">
                  <AlertTriangle size={18} />
                  <h4 className="font-display font-semibold text-sm">Low Inventory replenishment alerts ({alerts.lowStock.length})</h4>
                </div>
                <div className="space-y-2 max-h-[150px] overflow-y-auto pr-1">
                  {alerts.lowStock.map(p => (
                    <div key={p.id} className="flex justify-between items-center text-xs text-amber-900 bg-white border border-amber-100/50 p-2.5 rounded-xl">
                      <span className="font-medium truncate max-w-[70%]">{p.name}</span>
                      <span className="font-mono font-bold text-amber-600">
                        {p.currentStock} left (Min: {p.minStockLevel})
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Expiration warning alerts */}
          {alerts.expiring.length > 0 && (
            <div className="bg-red-50/40 border border-red-100 rounded-2xl p-5 shadow-sm flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-2 text-red-800 mb-3">
                  <AlertTriangle size={18} />
                  <h4 className="font-display font-semibold text-sm">Critical expiration warnings ({alerts.expiring.length})</h4>
                </div>
                <div className="space-y-2 max-h-[150px] overflow-y-auto pr-1">
                  {alerts.expiring.map(p => (
                    <div key={p.id} className="flex justify-between items-center text-xs text-red-900 bg-white border border-red-100/50 p-2.5 rounded-xl">
                      <span className="font-medium truncate max-w-[70%]">{p.name}</span>
                      <span className="font-mono font-bold text-red-600">
                        Expires: {p.expirationDate}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Charts section */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Sales Trend Line (Left 8 Columns) */}
        <div className="lg:col-span-8 bg-white border border-slate-100 rounded-2xl p-6 shadow-sm">
          <h3 className="font-display font-semibold text-slate-800 text-sm mb-4">Financial Velocity Trend</h3>
          <div className="h-72">
            {salesTrendData.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={salesTrendData} margin={{ top: 10, right: 10, left: -15, bottom: 0 }}>
                  <defs>
                    <linearGradient id="colorRevenue" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#4f46e5" stopOpacity={0.2}/>
                      <stop offset="95%" stopColor="#4f46e5" stopOpacity={0}/>
                    </linearGradient>
                    <linearGradient id="colorProfit" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#10b981" stopOpacity={0.2}/>
                      <stop offset="95%" stopColor="#10b981" stopOpacity={0}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                  <XAxis dataKey="name" stroke="#94a3b8" fontSize={9} tickLine={false} axisLine={false} />
                  <YAxis stroke="#94a3b8" fontSize={9} tickLine={false} axisLine={false} />
                  <Tooltip 
                    contentStyle={{ backgroundColor: '#ffffff', borderRadius: '12px', border: '1px solid #e2e8f0', fontFamily: 'Inter' }}
                    labelStyle={{ fontWeight: 'bold', fontSize: '10px', color: '#1e293b' }}
                  />
                  <Legend verticalAlign="top" height={36} iconType="circle" wrapperStyle={{ fontSize: '11px', fontFamily: 'Inter' }} />
                  <Area type="monotone" dataKey="Revenue" stroke="#4f46e5" strokeWidth={2} fillOpacity={1} fill="url(#colorRevenue)" />
                  <Area type="monotone" dataKey="Profit" stroke="#10b981" strokeWidth={2} fillOpacity={1} fill="url(#colorProfit)" />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-full flex items-center justify-center text-slate-400 text-xs">
                No Sales registered in selected periods
              </div>
            )}
          </div>
        </div>

        {/* Category Contribution Pie (Right 4 Columns) */}
        <div className="lg:col-span-4 bg-white border border-slate-100 rounded-2xl p-6 shadow-sm flex flex-col justify-between">
          <h3 className="font-display font-semibold text-slate-800 text-sm mb-4">Sales by Commodity Category</h3>
          <div className="h-56 relative flex items-center justify-center">
            {categoryDistributionData.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={categoryDistributionData}
                    cx="50%"
                    cy="50%"
                    innerRadius={55}
                    outerRadius={80}
                    paddingAngle={3}
                    dataKey="value"
                  >
                    {categoryDistributionData.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => `shs ${Number(value).toLocaleString()}`} />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="text-slate-400 text-xs">
                No categorical sales logged
              </div>
            )}
          </div>
          <div className="space-y-1.5 mt-2 max-h-[100px] overflow-y-auto pr-1 no-scrollbar">
            {categoryDistributionData.map((entry, index) => (
              <div key={entry.name} className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-1.5 min-w-0">
                  <span className="h-2 w-2 rounded-full shrink-0" style={{ backgroundColor: COLORS[index % COLORS.length] }} />
                  <span className="text-slate-600 truncate">{entry.name}</span>
                </div>
                <span className="font-mono font-medium text-slate-900">shs {entry.value.toLocaleString()}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Commodity Popularity Leaderboard (Bought Most) */}
      <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-4">
          <div>
            <h3 className="font-display font-semibold text-slate-800 text-sm">🛒 Commodity Popularity & Sales Leaderboard (Bought Most)</h3>
            <p className="text-xs text-slate-400 mt-0.5">Top performing commodities sorted by total units sold during the selected scope</p>
          </div>
          <div className="bg-slate-50 border border-slate-200/50 px-3 py-1.5 rounded-lg text-xs font-mono text-slate-600">
            Total Commodities Sold: {topCommodities.reduce((acc, c) => acc + c.quantity, 0).toLocaleString()} units
          </div>
        </div>

        <div className="overflow-x-auto border border-slate-100 rounded-xl">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-50 text-slate-400 font-display font-bold text-[10px] tracking-wider uppercase border-b border-slate-100">
                <th className="py-3 px-4">Rank / SKU</th>
                <th className="py-3 px-4">Commodity Name</th>
                <th className="py-3 px-4">Category</th>
                <th className="py-3 px-4 text-center">Units Sold</th>
                <th className="py-3 px-4 text-right">Total Revenue</th>
                <th className="py-3 px-4 text-right">Total Profit</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 text-slate-700 text-xs font-medium">
              {topCommodities.slice(0, 10).map((c, idx) => {
                const maxQty = topCommodities[0]?.quantity || 1;
                const percent = Math.min(100, Math.round((c.quantity / maxQty) * 100));

                return (
                  <tr key={c.id} className="hover:bg-slate-50/50 transition-colors">
                    <td className="py-3 px-4">
                      <div className="flex items-center gap-2">
                        <span className={`h-5 w-5 rounded-full flex items-center justify-center font-display font-bold text-[10px] ${
                          idx === 0 
                            ? 'bg-amber-100 text-amber-800' 
                            : idx === 1 
                            ? 'bg-slate-200 text-slate-800' 
                            : idx === 2 
                            ? 'bg-orange-100 text-orange-800' 
                            : 'bg-slate-100 text-slate-600'
                        }`}>
                          {idx + 1}
                        </span>
                        <span className="font-mono text-[9px] text-slate-400">{c.sku || 'N/A'}</span>
                      </div>
                    </td>
                    <td className="py-3 px-4">
                      <span className="font-display font-semibold text-slate-800">{c.name}</span>
                    </td>
                    <td className="py-3 px-4">
                      <span className="bg-slate-100 border border-slate-200/40 text-slate-600 px-2 py-0.5 rounded-md text-[9px] font-sans">
                        {c.category}
                      </span>
                    </td>
                    <td className="py-3 px-4">
                      <div className="flex flex-col items-center gap-1 min-w-[100px]">
                        <span className="font-mono font-bold text-slate-900">{c.quantity.toLocaleString()} units</span>
                        <div className="w-full bg-slate-100 h-1.5 rounded-full overflow-hidden">
                          <div 
                            className={`h-full rounded-full ${
                              idx === 0 
                                ? 'bg-amber-500' 
                                : idx === 1 
                                ? 'bg-indigo-500' 
                                : idx === 2 
                                ? 'bg-orange-500' 
                                : 'bg-slate-400'
                            }`}
                            style={{ width: `${percent}%` }}
                          />
                        </div>
                      </div>
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-semibold text-slate-900">
                      shs {c.revenue.toLocaleString()}
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-bold text-emerald-600">
                      shs {c.profit.toLocaleString()}
                    </td>
                  </tr>
                );
              })}

              {topCommodities.length === 0 && (
                <tr>
                  <td colSpan={6} className="py-10 text-center text-slate-400 font-display text-xs">
                    No sales logs mapped during this period
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Automatic Balance EOD Results Display Modal/Panel */}
      <AnimatePresence>
        {activeEodReport && (
          <motion.div 
            initial={{ opacity: 0, y: 15 }} 
            animate={{ opacity: 1, y: 0 }} 
            exit={{ opacity: 0, y: 15 }}
            className="bg-slate-900 text-slate-100 rounded-2xl p-6 shadow-xl border border-slate-800 relative overflow-hidden"
          >
            {/* Ambient Background Glow */}
            <div className="absolute top-0 right-0 w-64 h-64 bg-indigo-500/10 rounded-full blur-3xl -z-10" />

            <div className="flex flex-col md:flex-row justify-between gap-6">
              <div className="space-y-4 flex-1">
                <div className="flex items-center gap-2">
                  <div className="p-1.5 bg-indigo-500/20 text-indigo-400 rounded-lg">
                    <Sparkles size={16} />
                  </div>
                  <span className="text-xs font-display font-bold tracking-wider text-indigo-400 uppercase">EOD Balancing Active Report - {activeEodReport.date}</span>
                </div>

                <h3 className="font-display font-extrabold text-xl tracking-tight text-white leading-snug">
                  Day successfully balanced. Profit margin locked!
                </h3>

                {parsedAiInsights ? (
                  <div className="space-y-4 text-xs text-slate-300 leading-relaxed font-sans">
                    <p>{parsedAiInsights.eodSummaryText}</p>
                    
                    {/* Advice */}
                    <div>
                      <h4 className="font-display font-bold text-white text-xs mb-2 flex items-center gap-1.5 text-indigo-400">
                        <CheckCircle2 size={12} /> Strategic Business Insights (Gemini AI):
                      </h4>
                      <ul className="space-y-2 pl-4 list-disc text-slate-300">
                        {parsedAiInsights.strategicAdvice?.map((adv: string, idx: number) => (
                          <li key={idx}>{adv}</li>
                        ))}
                      </ul>
                    </div>
                  </div>
                ) : (
                  <p className="text-xs text-slate-300">Evaluating inventory capital turnover...</p>
                )}
              </div>

              {/* Side controls */}
              <div className="md:w-72 bg-slate-800/50 rounded-xl p-5 border border-slate-800 flex flex-col justify-between">
                <div className="space-y-3">
                  <div className="flex justify-between text-xs border-b border-slate-700 pb-2">
                    <span className="text-slate-400">Balanced Sales:</span>
                    <span className="font-mono font-bold text-white">shs {activeEodReport.totalSales.toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-xs border-b border-slate-700 pb-2">
                    <span className="text-slate-400">Staked Capital:</span>
                    <span className="font-mono font-bold text-white">shs {activeEodReport.totalStaked.toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between text-xs border-b border-slate-700 pb-2">
                    <span className="text-slate-400">Net Profit Made:</span>
                    <span className="font-mono font-bold text-emerald-400">shs {activeEodReport.totalProfit.toLocaleString()}</span>
                  </div>
                </div>

                <div className="mt-6 space-y-3">
                  <button
                    onClick={() => setShowNotificationModal(true)}
                    className="w-full bg-indigo-600 hover:bg-indigo-500 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-md flex items-center justify-center gap-1.5"
                  >
                    <Mail size={13} />
                    Send Summary to Owner
                  </button>
                  <button
                    onClick={() => setActiveEodReport(null)}
                    className="w-full bg-slate-800 hover:bg-slate-750 text-slate-400 hover:text-slate-200 rounded-xl py-2.5 font-display font-medium text-xs transition-all text-center"
                  >
                    Dismiss Report
                  </button>
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Send Dispatch Summary to Owner Modal */}
      <AnimatePresence>
        {showNotificationModal && activeEodReport && (
          <div className="fixed inset-0 bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
            <div className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden border border-slate-100 flex flex-col p-6 space-y-5">
              <div className="flex items-center gap-3">
                <div className="p-2.5 bg-indigo-50 text-indigo-600 rounded-xl">
                  <Mail size={18} />
                </div>
                <div>
                  <h3 className="font-display font-bold text-slate-900 text-sm">Send Dispatch Ledger</h3>
                  <p className="text-xs text-slate-400">Notify the business owner with today's figures</p>
                </div>
              </div>

              {/* Phone contact input */}
              <div>
                <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                  Owner Contact Number
                </label>
                <input
                  type="text"
                  value={ownerContact}
                  onChange={(e) => setOwnerContact(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                />
              </div>

              {/* Msg draft */}
              <div>
                <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                  Notification Draft
                </label>
                <textarea
                  readOnly
                  rows={6}
                  value={parsedAiInsights?.ownerMessageDraft || `🛒 SUPERMARKET EOD REPORT - ${activeEodReport.date}\nTotal Sales: shs ${activeEodReport.totalSales.toLocaleString()}\nTotal Staked: shs ${activeEodReport.totalStaked.toLocaleString()}\nNet Profit: shs ${activeEodReport.totalProfit.toLocaleString()}\nNo. of Sales: ${activeEodReport.salesCount}`}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl p-3 text-[10px] font-mono focus:outline-none resize-none leading-relaxed text-slate-700"
                />
              </div>

              <div className="flex gap-3 pt-2">
                <button
                  onClick={handleSendNotification}
                  disabled={isSendingNotification}
                  className="flex-1 bg-slate-900 hover:bg-slate-800 disabled:bg-slate-400 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all flex items-center justify-center gap-1.5"
                >
                  {isSendingNotification ? (
                    <>
                      <span className="animate-spin rounded-full h-3.5 w-3.5 border-b-2 border-white"></span>
                      Sending SMS...
                    </>
                  ) : (
                    <>
                      <CheckCircle2 size={13} />
                      Confirm & Send
                    </>
                  )}
                </button>
                <button
                  onClick={() => setShowNotificationModal(false)}
                  className="px-4 bg-white hover:bg-slate-50 border border-slate-200 text-slate-600 rounded-xl py-2.5 font-display font-medium text-xs transition-all"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};
export default DashboardView;
