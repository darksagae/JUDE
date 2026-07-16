import React, { useState, useMemo } from 'react';
import { Loan, UserSession, loanBalance, loanSettled } from '../types';
import { localDB } from '../utils/localDB';
import {
  HandCoins, Search, X, Check, Trash2, ShieldAlert, Phone,
  CalendarClock, User, Receipt, Wallet
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';

interface LoansViewProps {
  onRefresh?: () => void;
}

const shs = (n: number) => 'shs ' + Math.round(n).toLocaleString();

const fmtDate = (iso?: string) => {
  if (!iso) return '—';
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : d.toLocaleString([], {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
  });
};

export const LoansView: React.FC<LoansViewProps> = ({ onRefresh }) => {
  const [currentSession] = useState<UserSession>(() => localDB.getSession());
  const [loans, setLoans] = useState<Loan[]>(() => localDB.getLoans());
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<'all' | 'active' | 'settled'>('all');
  const [selected, setSelected] = useState<Loan | null>(null);
  const [payAmount, setPayAmount] = useState('');
  const [modalError, setModalError] = useState('');
  const [modalSuccess, setModalSuccess] = useState('');

  const isTopManager = currentSession.role === 'top_manager';

  const reload = () => {
    const fresh = localDB.getLoans();
    setLoans(fresh);
    if (selected) setSelected(fresh.find(l => l.id === selected.id) ?? null);
    onRefresh?.();
  };

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return loans.filter(l => {
      if (filter === 'active' && loanSettled(l)) return false;
      if (filter === 'settled' && !loanSettled(l)) return false;
      if (!q) return true;
      return (
        l.customerName.toLowerCase().includes(q) ||
        l.customerContact.includes(q) ||
        l.id.toLowerCase().includes(q)
      );
    });
  }, [loans, query, filter]);

  const totals = useMemo(() => {
    let outstanding = 0;
    let collected = 0;
    for (const l of loans) {
      outstanding += loanBalance(l);
      collected += l.amountPaid;
    }
    return { outstanding, collected, count: loans.length };
  }, [loans]);

  const openLoan = (loan: Loan) => {
    setSelected(loan);
    setPayAmount('');
    setModalError('');
    setModalSuccess('');
  };

  const handleRecordPayment = () => {
    if (!selected) return;
    setModalError('');
    setModalSuccess('');

    const amount = Number(payAmount);
    if (!payAmount.trim() || isNaN(amount) || amount <= 0) {
      setModalError('Enter a payment amount greater than zero.');
      return;
    }
    const balance = loanBalance(selected);
    if (balance <= 0) {
      setModalError('This loan is already fully settled.');
      return;
    }
    if (amount > balance) {
      setModalError(`Payment exceeds the outstanding balance of ${shs(balance)}.`);
      return;
    }

    localDB.recordLoanPayment(selected.id, amount);
    setPayAmount('');
    setModalSuccess(`Received ${shs(amount)}. Balance updated.`);
    reload();
  };

  const handleDelete = async (loan: Loan) => {
    if (!isTopManager) return;
    if (!window.confirm(`Permanently delete loan ${loan.id} for ${loan.customerName}? This removes it from the cloud database for every terminal.`)) {
      return;
    }
    await localDB.deleteLoan(loan.id);
    setSelected(null);
    reload();
  };

  return (
    <div className="space-y-6 font-sans">

      {/* Header + summary tiles */}
      <div className="bg-slate-900 border border-slate-800 text-white rounded-2xl p-6 shadow-md relative overflow-hidden">
        <div className="absolute right-0 top-0 translate-x-12 -translate-y-12 w-48 h-48 bg-amber-500/10 rounded-full blur-2xl" />
        <div className="flex items-center gap-3.5 mb-5">
          <div className="p-3 rounded-xl bg-amber-500/20 text-amber-400">
            <HandCoins size={26} />
          </div>
          <div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-slate-400">
              Customer Credit Ledger
            </span>
            <h2 className="text-lg font-display font-black text-white leading-tight uppercase">
              Loans &amp; Credit
            </h2>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
          <div className="bg-slate-950/50 border border-slate-800 rounded-xl p-3.5">
            <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">Outstanding Balance</span>
            <p className="text-lg font-display font-black text-amber-400 mt-1">{shs(totals.outstanding)}</p>
          </div>
          <div className="bg-slate-950/50 border border-slate-800 rounded-xl p-3.5">
            <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">Total Collected</span>
            <p className="text-lg font-display font-black text-emerald-400 mt-1">{shs(totals.collected)}</p>
          </div>
          <div className="bg-slate-950/50 border border-slate-800 rounded-xl p-3.5">
            <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">Loan Records</span>
            <p className="text-lg font-display font-black text-white mt-1">{totals.count}</p>
          </div>
        </div>

        <p className="text-[10px] text-slate-400 mt-4 leading-relaxed">
          Loans are created only at the POS terminal when part of a sale is taken on credit. Profit on a credit
          sale is recognised here as the customer repays.
        </p>
      </div>

      {/* Search + filters */}
      <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm flex flex-col md:flex-row gap-3 items-stretch md:items-center">
        <div className="flex items-center gap-2 bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 flex-1">
          <Search size={14} className="text-slate-400 shrink-0" />
          <input
            type="text"
            placeholder="Search by customer name, contact, or loan ID..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="bg-transparent text-xs text-slate-800 flex-1 focus:outline-none"
          />
          {query && (
            <button onClick={() => setQuery('')} className="text-slate-400 hover:text-slate-700">
              <X size={13} />
            </button>
          )}
        </div>

        <div className="flex gap-2">
          {(['all', 'active', 'settled'] as const).map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3.5 py-2 rounded-xl text-[10px] font-display font-bold uppercase tracking-wider border transition-all ${
                filter === f
                  ? 'bg-slate-900 border-slate-900 text-white shadow-sm'
                  : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'
              }`}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      {/* Loan cards */}
      {visible.length === 0 ? (
        <div className="bg-white border border-slate-100 rounded-2xl p-12 text-center shadow-sm">
          <div className="inline-flex p-4 bg-slate-50 text-slate-300 rounded-full mb-3">
            <HandCoins size={28} />
          </div>
          <h3 className="font-display font-bold text-slate-900 text-sm">No loan records</h3>
          <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto leading-relaxed">
            {loans.length === 0
              ? 'Credit sales made at the POS terminal will appear here automatically.'
              : 'No loans match the current search or filter.'}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {visible.map(loan => {
            const balance = loanBalance(loan);
            const settled = loanSettled(loan);
            const paidPct = loan.originalAmount > 0
              ? Math.min(100, (loan.amountPaid / loan.originalAmount) * 100)
              : 100;

            return (
              <button
                key={loan.id}
                onClick={() => openLoan(loan)}
                className="text-left bg-white border border-slate-100 rounded-2xl p-5 shadow-sm hover:shadow-md hover:border-slate-200 transition-all space-y-3.5"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className={`p-2.5 rounded-xl shrink-0 ${
                      settled ? 'bg-emerald-50 text-emerald-600' : 'bg-amber-50 text-amber-600'
                    }`}>
                      <User size={18} />
                    </div>
                    <div>
                      <h4 className="font-display font-bold text-sm text-slate-900">{loan.customerName}</h4>
                      <p className="text-[10px] font-mono text-slate-400 mt-0.5">
                        {loan.customerContact} &bull; {loan.id}
                      </p>
                    </div>
                  </div>
                  <span className={`text-[9px] font-black uppercase tracking-wider px-2 py-1 rounded-full shrink-0 ${
                    settled ? 'bg-emerald-600 text-white' : 'bg-amber-500 text-white'
                  }`}>
                    {settled ? 'Settled' : 'Active'}
                  </span>
                </div>

                <div className="grid grid-cols-3 gap-2 text-center">
                  <div className="bg-slate-50 border border-slate-100 rounded-lg py-2">
                    <span className="block text-[8px] font-mono uppercase text-slate-400">Loaned</span>
                    <span className="block text-[11px] font-display font-bold text-slate-800 mt-0.5">{shs(loan.originalAmount)}</span>
                  </div>
                  <div className="bg-slate-50 border border-slate-100 rounded-lg py-2">
                    <span className="block text-[8px] font-mono uppercase text-slate-400">Paid</span>
                    <span className="block text-[11px] font-display font-bold text-emerald-600 mt-0.5">{shs(loan.amountPaid)}</span>
                  </div>
                  <div className="bg-slate-50 border border-slate-100 rounded-lg py-2">
                    <span className="block text-[8px] font-mono uppercase text-slate-400">Balance</span>
                    <span className={`block text-[11px] font-display font-bold mt-0.5 ${
                      settled ? 'text-slate-400' : 'text-amber-600'
                    }`}>{shs(balance)}</span>
                  </div>
                </div>

                <div className="h-1.5 bg-slate-100 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${settled ? 'bg-emerald-500' : 'bg-amber-500'}`}
                    style={{ width: `${paidPct}%` }}
                  />
                </div>

                <div className="flex items-center justify-between text-[10px] text-slate-400 font-mono">
                  <span className="flex items-center gap-1">
                    <CalendarClock size={11} /> Pledged {loan.pledgeDate}
                  </span>
                  <span>Tap for details</span>
                </div>
              </button>
            );
          })}
        </div>
      )}

      {/* Loan detail modal */}
      <AnimatePresence>
        {selected && (
          <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 10 }}
              className="bg-white rounded-2xl shadow-2xl max-w-lg w-full overflow-hidden border border-slate-100"
            >
              {/* Modal header */}
              <div className="bg-slate-950 px-6 py-4 text-white flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <User className="text-amber-400 shrink-0" size={20} />
                  <div>
                    <h3 className="font-display font-black text-sm uppercase tracking-wide leading-tight">
                      {selected.customerName}
                    </h3>
                    <p className="text-[10px] text-slate-400 font-mono">{selected.id}</p>
                  </div>
                </div>
                <button
                  onClick={() => setSelected(null)}
                  className="text-slate-400 hover:text-white transition-colors p-1"
                >
                  <X size={18} />
                </button>
              </div>

              <div className="p-6 space-y-5 max-h-[70vh] overflow-y-auto">
                {modalSuccess && (
                  <div className="bg-emerald-50 border border-emerald-100 rounded-xl p-3 text-xs text-emerald-700 flex items-center gap-2">
                    <Check size={14} className="shrink-0" />
                    <span>{modalSuccess}</span>
                  </div>
                )}
                {modalError && (
                  <div className="bg-rose-50 border border-rose-100 rounded-xl p-3 text-xs text-rose-700 flex items-center gap-2">
                    <ShieldAlert size={14} className="shrink-0" />
                    <span>{modalError}</span>
                  </div>
                )}

                {/* Customer details */}
                <div className="bg-slate-50 border border-slate-100 rounded-xl p-4 space-y-2 text-[11px]">
                  <DetailRow icon={<Phone size={11} />} label="Contact" value={selected.customerContact} />
                  <DetailRow icon={<CalendarClock size={11} />} label="Pledged repayment" value={selected.pledgeDate} />
                  <DetailRow icon={<Receipt size={11} />} label="Origin sale" value={selected.saleId || 'Not linked'} />
                  <DetailRow icon={<User size={11} />} label="Registered by" value={`${selected.createdByName} (${selected.createdById})`} />
                  <DetailRow icon={<CalendarClock size={11} />} label="Created" value={fmtDate(selected.createdAt)} />
                  {selected.settledAt && (
                    <DetailRow icon={<Check size={11} />} label="Settled on" value={fmtDate(selected.settledAt)} />
                  )}
                  {selected.notes && (
                    <DetailRow icon={<Receipt size={11} />} label="Notes" value={selected.notes} />
                  )}
                </div>

                {/* Money summary */}
                <div className="grid grid-cols-3 gap-2 text-center">
                  <div className="bg-white border border-slate-200 rounded-xl py-2.5">
                    <span className="block text-[8px] font-mono uppercase text-slate-400">Loaned</span>
                    <span className="block text-xs font-display font-bold text-slate-800 mt-0.5">{shs(selected.originalAmount)}</span>
                  </div>
                  <div className="bg-white border border-slate-200 rounded-xl py-2.5">
                    <span className="block text-[8px] font-mono uppercase text-slate-400">Paid</span>
                    <span className="block text-xs font-display font-bold text-emerald-600 mt-0.5">{shs(selected.amountPaid)}</span>
                  </div>
                  <div className="bg-white border border-slate-200 rounded-xl py-2.5">
                    <span className="block text-[8px] font-mono uppercase text-slate-400">Balance</span>
                    <span className="block text-xs font-display font-bold text-amber-600 mt-0.5">{shs(loanBalance(selected))}</span>
                  </div>
                </div>

                {/* Record payment */}
                {!loanSettled(selected) ? (
                  <div className="bg-emerald-50/50 border border-emerald-100 rounded-xl p-4 space-y-3">
                    <div className="flex items-center gap-2">
                      <Wallet size={14} className="text-emerald-600" />
                      <h4 className="font-display font-bold text-[10px] uppercase tracking-wide text-emerald-900">
                        Record a Repayment
                      </h4>
                    </div>
                    <div className="flex gap-2">
                      <input
                        type="number"
                        min="1"
                        placeholder={`Max ${loanBalance(selected)}`}
                        value={payAmount}
                        onChange={(e) => setPayAmount(e.target.value)}
                        className="flex-1 bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 text-slate-800"
                      />
                      <button
                        type="button"
                        onClick={() => setPayAmount(String(loanBalance(selected)))}
                        className="px-3 py-2 bg-white border border-slate-200 hover:bg-slate-50 text-slate-600 rounded-xl text-[10px] font-display font-bold uppercase tracking-wider transition-all"
                      >
                        Pay Off
                      </button>
                      <button
                        type="button"
                        onClick={handleRecordPayment}
                        className="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-[10px] font-display font-bold uppercase tracking-wider shadow-sm transition-all"
                      >
                        Record
                      </button>
                    </div>
                    <p className="text-[9px] text-emerald-900/60 leading-normal">
                      Profit on this credit sale is recognised proportionally as cash is received.
                    </p>
                  </div>
                ) : (
                  <div className="bg-emerald-50 border border-emerald-100 rounded-xl p-3.5 text-xs text-emerald-700 flex items-center gap-2">
                    <Check size={14} className="shrink-0" />
                    <span className="font-medium">This loan is fully settled. No balance remains.</span>
                  </div>
                )}

                {/* Payment history */}
                <div className="space-y-2">
                  <h4 className="font-display font-bold text-[10px] uppercase tracking-wide text-slate-500">
                    Payment History ({selected.payments.length})
                  </h4>
                  {selected.payments.length === 0 ? (
                    <p className="text-[11px] text-slate-400 bg-slate-50 border border-slate-100 rounded-xl p-3">
                      No repayments received yet.
                    </p>
                  ) : (
                    <div className="border border-slate-100 rounded-xl divide-y divide-slate-100 overflow-hidden">
                      {selected.payments.map(p => (
                        <div key={p.id} className="flex items-center justify-between px-3.5 py-2.5 bg-white">
                          <div>
                            <span className="block text-xs font-display font-bold text-emerald-600">{shs(p.amount)}</span>
                            <span className="block text-[9px] font-mono text-slate-400 mt-0.5">
                              Received by {p.receivedByName} ({p.receivedById})
                            </span>
                          </div>
                          <span className="text-[9px] font-mono text-slate-400 text-right">{fmtDate(p.timestamp)}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              {/* Modal footer */}
              <div className="p-4 bg-slate-50 border-t border-slate-100 flex gap-2">
                <button
                  type="button"
                  onClick={() => setSelected(null)}
                  className="flex-1 bg-white hover:bg-slate-100 border border-slate-200 text-slate-700 rounded-xl py-2 font-display font-bold text-[10px] uppercase tracking-wider transition-all"
                >
                  Close
                </button>
                {isTopManager && (
                  <button
                    type="button"
                    onClick={() => handleDelete(selected)}
                    className="flex-1 bg-rose-600 hover:bg-rose-700 text-white rounded-xl py-2 font-display font-bold text-[10px] uppercase tracking-wider transition-all shadow-md flex items-center justify-center gap-1.5"
                  >
                    <Trash2 size={11} /> Delete Loan
                  </button>
                )}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};

const DetailRow: React.FC<{ icon: React.ReactNode; label: string; value: string }> = ({ icon, label, value }) => (
  <div className="flex items-start justify-between gap-3 border-b border-slate-200/50 last:border-0 pb-1.5 last:pb-0">
    <span className="flex items-center gap-1.5 text-slate-400 shrink-0">
      {icon} {label}
    </span>
    <span className="font-bold text-slate-700 font-mono text-right break-all">{value}</span>
  </div>
);

export default LoansView;
