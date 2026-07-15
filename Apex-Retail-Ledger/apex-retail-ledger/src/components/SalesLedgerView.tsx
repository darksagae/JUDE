import React, { useState, useEffect } from 'react';
import { Sale } from '../types';
import localDB from '../utils/localDB';
import { 
  Receipt, Trash2, ShieldAlert, Calendar, User, CreditCard, 
  Search, RefreshCw, Printer, AlertCircle, ShoppingCart, ArrowLeft 
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ThermalReceipt from './ThermalReceipt';

interface SalesLedgerViewProps {
  onRefresh: () => void;
  role: 'top_manager' | 'manager' | 'worker';
}

export const SalesLedgerView: React.FC<SalesLedgerViewProps> = ({ onRefresh, role }) => {
  const [sales, setSales] = useState<Sale[]>(() => localDB.getSales());
  const [selectedSale, setSelectedSale] = useState<Sale | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isDeletingId, setIsDeletingId] = useState<string | null>(null);
  const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);

  useEffect(() => {
    // Sync local list on load
    setSales(localDB.getSales());
  }, []);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    setMessage(null);
    try {
      if (localDB.isOfflineMode()) {
        setSales(localDB.getSales());
        setMessage({ type: 'error', text: 'Offline Mode: Reading offline sales history only.' });
      } else {
        await localDB.triggerSync();
        setSales(localDB.getSales());
        onRefresh();
        setMessage({ type: 'success', text: 'Successfully pulled transaction ledger updates!' });
      }
    } catch (err) {
      setMessage({ type: 'error', text: 'Cloud pull deferred. Offline ledger fallback loaded.' });
    } finally {
      setIsRefreshing(false);
      setTimeout(() => setMessage(null), 3000);
    }
  };

  const handleVoidSale = async (saleId: string) => {
    if (role !== 'manager' && role !== 'top_manager') {
      alert("Unauthorized shift credentials. Only managers and top managers can void/delete transactions.");
      return;
    }

    if (!confirm(`Are you absolutely sure you want to VOID transaction ${saleId}? This will delete the sale record and automatically replenish stock levels.`)) {
      return;
    }

    setIsDeletingId(saleId);
    setMessage(null);

    const session = localDB.getSession();

    try {
      // If offline, void locally
      if (localDB.isOfflineMode()) {
        const localSales = localDB.getSales();
        const saleIdx = localSales.findIndex(s => s.id === saleId);
        if (saleIdx !== -1) {
          const voidedSale = localSales[saleIdx];
          
          // Replenish stock locally
          const localProds = localDB.getProducts();
          voidedSale.items.forEach(item => {
            const p = localProds.find(prod => prod.id === item.productId);
            if (p) p.currentStock += item.quantity;
          });
          localDB.setProducts(localProds);

          // Remove sale
          localSales.splice(saleIdx, 1);
          localDB.setSales(localSales);

          // Log action
          localDB.logAction(session.userId, session.name, session.role, 'SALE_VOID', `Voided sale ${saleId} offline. Stock replenished.`);
          
          setSales(localSales);
          setSelectedSale(null);
          onRefresh();
          setMessage({ type: 'success', text: 'Transaction voided locally (Offline).' });
        }
      } else {
        // Send to server
        const response = await fetch('/api/sales/delete', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            saleId,
            role: session.role,
            userId: session.userId,
            userName: session.name
          })
        });

        if (!response.ok) {
          const errData = await response.json();
          throw new Error(errData.message || 'Server error voiding transaction');
        }

        const data = await response.json();
        
        if (data.success) {
          // Double-sided sync: overwrite local storage lists
          if (data.sales) {
            const resolvedSales = data.sales.map((s: any) => ({ ...s, synced: true }));
            localDB.setSales(resolvedSales);
            setSales(resolvedSales);
          }
          if (data.products) localDB.setProducts(data.products);
          if (data.stockTransactions) localDB.setTransactions(data.stockTransactions);
          if (data.auditLogs) localStorage.setItem('apex_audit_logs', JSON.stringify(data.auditLogs));
          
          setSelectedSale(null);
          onRefresh();
          setMessage({ type: 'success', text: `Transaction ${saleId} voided successfully. Stock restored!` });
        }
      }
    } catch (err: any) {
      console.error(err);
      setMessage({ type: 'error', text: `Failed to void transaction: ${err.message}` });
    } finally {
      setIsDeletingId(null);
      setTimeout(() => setMessage(null), 3000);
    }
  };

  const filteredSales = sales.filter(s => {
    const term = searchQuery.toLowerCase();
    return s.id.toLowerCase().includes(term) || 
           s.cashierName.toLowerCase().includes(term) || 
           s.cashierId.toLowerCase().includes(term) ||
           s.items.some(it => it.productName.toLowerCase().includes(term));
  });

  const getPaymentMethodLabel = (method: string) => {
    switch (method) {
      case 'cash': return 'Cash';
      case 'mobile_money': return 'Mobile Money';
      case 'card': return 'Bank Card';
      default: return method;
    }
  };

  return (
    <div className="space-y-6">
      {/* Header Panel */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h2 className="text-xl font-display font-black text-slate-800 tracking-tight flex items-center gap-2">
            <Receipt className="text-indigo-600" size={24} />
            TRANSACTION & SALES LEDGER
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Real-time completed receipts directory. Both staff and supervisors can verify records.
          </p>
        </div>

        <div className="flex items-center gap-3 w-full md:w-auto">
          <button
            onClick={handleRefresh}
            disabled={isRefreshing}
            className={`px-4 py-2 bg-white hover:bg-slate-50 border border-slate-200 text-slate-700 rounded-xl text-xs font-semibold flex items-center gap-2 transition-all shadow-sm ${
              isRefreshing ? 'opacity-50 cursor-not-allowed' : ''
            }`}
          >
            <RefreshCw size={14} className={isRefreshing ? 'animate-spin' : ''} />
            {isRefreshing ? 'Pulling Logs...' : 'Pull Cloud Updates'}
          </button>
        </div>
      </div>

      {/* Banner message */}
      <AnimatePresence>
        {message && (
          <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            className={`p-3.5 rounded-xl text-xs flex items-center gap-2.5 border ${
              message.type === 'success' 
                ? 'bg-emerald-50 text-emerald-800 border-emerald-100' 
                : 'bg-indigo-50 text-indigo-800 border-indigo-100'
            }`}
          >
            <AlertCircle size={15} />
            <span className="font-sans font-medium">{message.text}</span>
          </motion.div>
        )}
      </AnimatePresence>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* Transaction History Directory (Left 7/12) */}
        <div className="lg:col-span-7 bg-white rounded-2xl border border-slate-100 p-6 shadow-sm flex flex-col h-[calc(100vh-200px)] min-h-[500px]">
          {/* Search bar */}
          <div className="relative mb-4">
            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
            <input
              type="text"
              placeholder="Search by Transaction ID, item name, or cashier..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full bg-slate-50 border border-slate-200 rounded-xl py-2 pl-10 pr-4 text-xs font-sans placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 transition-all text-slate-800"
            />
          </div>

          {/* Table / List */}
          <div className="flex-1 overflow-y-auto pr-1 no-scrollbar space-y-3">
            {filteredSales.length === 0 ? (
              <div className="flex flex-col items-center justify-center text-center py-20 text-slate-400 space-y-3">
                <ShoppingCart size={32} />
                <p className="text-xs font-sans">No completed transactions matched your search criteria.</p>
              </div>
            ) : (
              filteredSales.map(sale => {
                const isSelected = selectedSale?.id === sale.id;
                return (
                  <div
                    key={sale.id}
                    onClick={() => setSelectedSale(sale)}
                    className={`p-4 border rounded-xl cursor-pointer transition-all ${
                      isSelected 
                        ? 'border-indigo-600 bg-indigo-50/40 shadow-sm' 
                        : 'border-slate-100 hover:border-slate-200 bg-white hover:bg-slate-50'
                    }`}
                  >
                    <div className="flex justify-between items-start mb-2.5">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-mono font-bold text-slate-800 text-xs">{sale.id}</span>
                          {!sale.synced && (
                            <span className="text-[8px] bg-amber-100 text-amber-800 font-black px-1.5 py-0.5 rounded uppercase">
                              Offline Cache
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-2 text-[10px] text-slate-400 mt-1 font-mono">
                          <Calendar size={10} />
                          <span>{new Date(sale.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} &bull; {new Date(sale.timestamp).toLocaleDateString()}</span>
                        </div>
                      </div>
                      <div className="text-right">
                        <span className="font-display font-black text-slate-900 text-sm">
                          shs {sale.totalAmount.toLocaleString()}
                        </span>
                        <div className="text-[9px] text-slate-400 uppercase font-mono mt-0.5">
                          {getPaymentMethodLabel(sale.paymentMethod)}
                        </div>
                      </div>
                    </div>

                    <div className="flex justify-between items-center text-[10px] text-slate-500 font-sans border-t border-slate-100/60 pt-2.5">
                      <div className="flex items-center gap-1">
                        <User size={11} className="text-slate-400" />
                        <span>Cashier: <strong className="text-slate-700">{sale.cashierName}</strong> ({sale.cashierId})</span>
                      </div>
                      <span className="text-slate-400">{sale.items.reduce((acc, i) => acc + i.quantity, 0)} items sold</span>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Selected Transaction Inspector & Receipt (Right 5/12) */}
        <div className="lg:col-span-5 space-y-4">
          {selectedSale ? (
            <div className="bg-white rounded-2xl border border-slate-100 p-6 shadow-sm space-y-6">
              <div className="flex justify-between items-center pb-4 border-b border-slate-100">
                <div>
                  <h3 className="font-display font-bold text-slate-900 text-xs uppercase tracking-wider">Transaction Detail</h3>
                  <span className="text-[10px] font-mono text-indigo-600 font-bold">{selectedSale.id}</span>
                </div>
                {role === 'manager' ? (
                  <button
                    onClick={() => handleVoidSale(selectedSale.id)}
                    disabled={isDeletingId === selectedSale.id}
                    className="bg-red-50 hover:bg-red-100 text-red-600 border border-red-100 rounded-xl px-3.5 py-2 text-xs font-semibold flex items-center gap-1.5 transition-all"
                  >
                    <Trash2 size={13} />
                    {isDeletingId === selectedSale.id ? 'Voiding...' : 'Void Sale'}
                  </button>
                ) : (
                  <div className="bg-slate-100 text-slate-500 rounded-xl px-3 py-1.5 text-[9px] font-mono flex items-center gap-1.5 border border-slate-200">
                    <ShieldAlert size={11} />
                    Manager Only Void
                  </div>
                )}
              </div>

              {/* Items Summary list */}
              <div className="space-y-2.5">
                <span className="block text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider">
                  Receipt Snapshot
                </span>
                <div className="max-h-[160px] overflow-y-auto space-y-1.5 pr-1 border border-slate-50 bg-slate-50/50 p-3 rounded-xl no-scrollbar">
                  {selectedSale.items.map((item, idx) => (
                    <div key={idx} className="flex justify-between text-xs font-sans">
                      <span className="text-slate-700 font-medium">{item.productName} <span className="text-slate-400 font-normal">x{item.quantity}</span></span>
                      <span className="font-mono text-slate-600">shs {(item.sellingPrice * item.quantity).toLocaleString()}</span>
                    </div>
                  ))}
                </div>
              </div>

              {/* Payment info */}
              <div className="grid grid-cols-2 gap-4 bg-slate-50/30 p-3.5 rounded-xl border border-slate-100 text-[11px] font-sans">
                <div>
                  <span className="text-slate-400 block font-medium">Payment Method</span>
                  <span className="text-slate-800 font-bold mt-0.5 block flex items-center gap-1">
                    <CreditCard size={11} className="text-slate-400" />
                    {getPaymentMethodLabel(selectedSale.paymentMethod)}
                  </span>
                  {selectedSale.paymentMethod === 'mobile_money' && selectedSale.mobileMoneyTxId && (
                    <span className="text-[10px] text-indigo-600 font-bold block mt-1 font-mono">
                      TxID: {selectedSale.mobileMoneyTxId}
                    </span>
                  )}
                </div>
                <div>
                  <span className="text-slate-400 block font-medium">Cashier Personnel</span>
                  <span className="text-slate-800 font-bold mt-0.5 block">{selectedSale.cashierName} ({selectedSale.cashierId})</span>
                </div>
                <div className="mt-2.5">
                  <span className="text-slate-400 block font-medium">Amount Tendered</span>
                  <span className="text-slate-800 font-semibold block">shs {selectedSale.amountPaid.toLocaleString()}</span>
                </div>
                <div className="mt-2.5">
                  <span className="text-slate-400 block font-medium">Change Given</span>
                  <span className="text-emerald-700 font-extrabold block">shs {selectedSale.changeDue.toLocaleString()}</span>
                </div>
              </div>

              {/* Real Receipt Preview panel */}
              <div className="border border-slate-100 rounded-2xl p-4 bg-slate-50/60 max-h-[350px] overflow-y-auto no-scrollbar">
                <div className="flex justify-between items-center mb-3">
                  <span className="text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider flex items-center gap-1.5">
                    <Printer size={12} />
                    Thermal Print Output
                  </span>
                  <button
                    onClick={() => {
                      const printContents = document.getElementById('thermal-ledger-output')?.innerHTML;
                      const originalContents = document.body.innerHTML;
                      if (printContents) {
                        const win = window.open('', '', 'height=600,width=400');
                        if (win) {
                          win.document.write('<html><head><title>Print Receipt</title><style>body {font-family: monospace; padding: 20px;}</style></head><body>');
                          win.document.write(printContents);
                          win.document.write('</body></html>');
                          win.document.close();
                          win.print();
                        }
                      }
                    }}
                    className="text-indigo-600 hover:text-indigo-700 text-[10px] font-bold flex items-center gap-1"
                  >
                    <Printer size={10} /> Print Output
                  </button>
                </div>
                <div id="thermal-ledger-output" className="bg-white border border-slate-150 p-4 rounded-xl shadow-inner scale-95 origin-top">
                  <ThermalReceipt sale={selectedSale} />
                </div>
              </div>
            </div>
          ) : (
            <div className="bg-slate-50 border border-slate-150 rounded-2xl p-8 text-center text-slate-400 flex flex-col items-center justify-center py-28 space-y-3">
              <div className="p-3.5 bg-slate-100 text-slate-500 rounded-full">
                <Receipt size={24} />
              </div>
              <p className="text-xs font-sans leading-relaxed max-w-xs">
                Select a completed transaction from the history list to view detailed receipt metrics, void records, or print physical thermal output.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
export default SalesLedgerView;
