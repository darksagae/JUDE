import React, { useState, useMemo } from 'react';
import { Expense, UserSession } from '../types';
import { localDB } from '../utils/localDB';
import {
  Wallet, Plus, Trash2, Check, ShieldAlert, Search, X, CalendarClock, Tag
} from 'lucide-react';

interface ExpensesViewProps {
  onRefresh?: () => void;
}

const shs = (n: number) => 'shs ' + Math.round(n).toLocaleString();

const fmtDate = (iso: string) => {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : d.toLocaleString([], {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
  });
};

export const ExpensesView: React.FC<ExpensesViewProps> = ({ onRefresh }) => {
  const [currentSession] = useState<UserSession>(() => localDB.getSession());
  const [expenses, setExpenses] = useState<Expense[]>(() => localDB.getExpenses());
  const [query, setQuery] = useState('');

  // Expenditure categories are shared through the cloud, so every terminal sees
  // the same list rather than a hard-coded one.
  const [categories, setCategories] = useState<string[]>(() => localDB.getExpenseCategories());
  const [category, setCategory] = useState(() => localDB.getExpenseCategories()[0] || '');
  const [newCategory, setNewCategory] = useState('');
  const [showCategoryManager, setShowCategoryManager] = useState(false);
  const [categoryMsg, setCategoryMsg] = useState('');

  const [description, setDescription] = useState('');
  const [amount, setAmount] = useState('');
  const [formError, setFormError] = useState('');
  const [formSuccess, setFormSuccess] = useState('');

  const isTopManager = currentSession.role === 'top_manager';

  const reload = () => {
    setExpenses(localDB.getExpenses());
    const cats = localDB.getExpenseCategories();
    setCategories(cats);
    if (!cats.includes(category)) setCategory(cats[0] || '');
    onRefresh?.();
  };

  const handleAddCategory = (e: React.FormEvent) => {
    e.preventDefault();
    setCategoryMsg('');
    const clean = newCategory.trim();
    if (!clean) return;
    if (!localDB.addExpenseCategory(clean)) {
      setCategoryMsg(`"${clean}" already exists.`);
      return;
    }
    setNewCategory('');
    setCategoryMsg(`Added "${clean}" — it will appear on every terminal.`);
    setCategories(localDB.getExpenseCategories());
    setCategory(clean);
  };

  const handleDeleteCategory = (cat: string) => {
    setCategoryMsg('');
    if (categories.length <= 1) {
      setCategoryMsg('At least one category must remain.');
      return;
    }
    if (!window.confirm(`Delete the "${cat}" category everywhere? Expenses already recorded under it keep their label.`)) return;
    localDB.deleteExpenseCategory(cat);
    const cats = localDB.getExpenseCategories();
    setCategories(cats);
    if (category === cat) setCategory(cats[0] || '');
    setCategoryMsg(`Deleted "${cat}" on every terminal.`);
  };

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return expenses;
    return expenses.filter(e =>
      e.description.toLowerCase().includes(q) ||
      e.category.toLowerCase().includes(q) ||
      e.id.toLowerCase().includes(q)
    );
  }, [expenses, query]);

  const totals = useMemo(() => {
    const now = new Date();
    let all = 0;
    let thisMonth = 0;
    for (const e of expenses) {
      all += e.amount;
      const d = new Date(e.timestamp);
      if (!isNaN(d.getTime()) && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()) {
        thisMonth += e.amount;
      }
    }
    return { all, thisMonth, count: expenses.length };
  }, [expenses]);

  const handleRecord = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError('');
    setFormSuccess('');

    const cleanDesc = description.trim();
    const value = Number(amount);

    if (!cleanDesc) {
      setFormError('A description is required so the expense can be audited.');
      return;
    }
    if (!amount.trim() || isNaN(value) || value <= 0) {
      setFormError('Enter an amount greater than zero.');
      return;
    }

    localDB.addExpense({ category, description: cleanDesc, amount: value });
    setFormSuccess(`Recorded ${shs(value)} under ${category}.`);
    setDescription('');
    setAmount('');
    reload();
  };

  const handleDelete = async (expense: Expense) => {
    if (!isTopManager) return;
    if (!window.confirm(`Permanently delete the ${shs(expense.amount)} ${expense.category} expense? This removes it from the cloud database for every terminal.`)) {
      return;
    }
    await localDB.deleteExpense(expense.id);
    reload();
  };

  return (
    <div className="grid grid-cols-1 xl:grid-cols-12 gap-6 items-start font-sans">

      {/* MAIN: summary + ledger */}
      <div className="xl:col-span-8 space-y-6">

        <div className="bg-slate-900 border border-slate-800 text-white rounded-2xl p-6 shadow-md relative overflow-hidden">
          <div className="absolute right-0 top-0 translate-x-12 -translate-y-12 w-48 h-48 bg-rose-500/10 rounded-full blur-2xl" />
          <div className="flex items-center gap-3.5 mb-5">
            <div className="p-3 rounded-xl bg-rose-500/20 text-rose-400">
              <Wallet size={26} />
            </div>
            <div>
              <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-slate-400">
                Operating Costs Ledger
              </span>
              <h2 className="text-lg font-display font-black text-white leading-tight uppercase">
                Business Expenses
              </h2>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
            <div className="bg-slate-950/50 border border-slate-800 rounded-xl p-3.5">
              <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">This Month</span>
              <p className="text-lg font-display font-black text-rose-400 mt-1">{shs(totals.thisMonth)}</p>
            </div>
            <div className="bg-slate-950/50 border border-slate-800 rounded-xl p-3.5">
              <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">All Time</span>
              <p className="text-lg font-display font-black text-white mt-1">{shs(totals.all)}</p>
            </div>
            <div className="bg-slate-950/50 border border-slate-800 rounded-xl p-3.5">
              <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500">Entries</span>
              <p className="text-lg font-display font-black text-white mt-1">{totals.count}</p>
            </div>
          </div>
        </div>

        {/* Search */}
        <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm">
          <div className="flex items-center gap-2 bg-slate-50 border border-slate-200 rounded-xl px-3 py-2">
            <Search size={14} className="text-slate-400 shrink-0" />
            <input
              type="text"
              placeholder="Search expenses by description, category, or ID..."
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
        </div>

        {/* Ledger list */}
        <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm space-y-5">
          <div className="flex justify-between items-center">
            <div>
              <h3 className="font-display font-bold text-slate-900 text-sm">Recorded Expenses</h3>
              <p className="text-xs text-slate-400 mt-0.5">Every entry is audit-logged and synced to the cloud database</p>
            </div>
            <span className="text-[10px] font-mono bg-slate-100 text-slate-500 px-2 py-1 rounded font-bold uppercase">
              {visible.length} Shown
            </span>
          </div>

          {visible.length === 0 ? (
            <div className="py-12 text-center">
              <div className="inline-flex p-4 bg-slate-50 text-slate-300 rounded-full mb-3">
                <Wallet size={28} />
              </div>
              <h4 className="font-display font-bold text-slate-900 text-sm">No expenses recorded</h4>
              <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto leading-relaxed">
                {expenses.length === 0
                  ? 'Use the form to log rent, transport, salaries, and other operating costs.'
                  : 'No expenses match the current search.'}
              </p>
            </div>
          ) : (
            <div className="divide-y divide-slate-100 border border-slate-100 rounded-xl overflow-hidden">
              {visible.map(expense => (
                <div key={expense.id} className="p-4 bg-white flex items-center justify-between gap-4 hover:bg-slate-50/40 transition-colors">
                  <div className="flex items-center gap-3.5 min-w-0">
                    <div className="p-2.5 rounded-xl bg-rose-50 text-rose-600 shrink-0">
                      <Wallet size={16} />
                    </div>
                    <div className="min-w-0">
                      <h4 className="font-display font-semibold text-xs text-slate-900 truncate">
                        {expense.description}
                      </h4>
                      <p className="text-[10px] font-mono text-slate-400 mt-0.5 truncate">
                        <span className="font-bold text-slate-600 uppercase">{expense.category}</span> &bull;{' '}
                        {expense.recordedByName} ({expense.recordedById})
                      </p>
                      <p className="text-[10px] font-mono text-slate-400 mt-0.5 flex items-center gap-1">
                        <CalendarClock size={10} /> {fmtDate(expense.timestamp)}
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center gap-3 shrink-0">
                    <span className="font-display font-black text-sm text-rose-600">-{shs(expense.amount)}</span>
                    {isTopManager && (
                      <button
                        onClick={() => handleDelete(expense)}
                        className="p-1.5 text-slate-300 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-all"
                        title="Delete this expense permanently"
                      >
                        <Trash2 size={13} />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* SIDE: record form */}
      <div className="xl:col-span-4">
        <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm space-y-4">
          <div className="flex items-center gap-2">
            <Plus size={16} className="text-slate-400" />
            <div>
              <h4 className="font-display font-bold text-slate-950 text-xs uppercase tracking-wide">Record an Expense</h4>
              <p className="text-[10px] text-slate-400 mt-0.5">Logged against your shift and synced immediately</p>
            </div>
          </div>

          {formSuccess && (
            <div className="bg-emerald-50 border border-emerald-100 rounded-xl p-3 text-xs text-emerald-700 flex items-center gap-2">
              <Check size={14} className="shrink-0" />
              <span>{formSuccess}</span>
            </div>
          )}

          {formError && (
            <div className="bg-rose-50 border border-rose-100 rounded-xl p-3 text-xs text-rose-700 flex items-center gap-2">
              <ShieldAlert size={14} className="shrink-0" />
              <span>{formError}</span>
            </div>
          )}

          <form onSubmit={handleRecord} className="space-y-3.5">
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider">
                  Category
                </label>
                <button
                  type="button"
                  onClick={() => { setShowCategoryManager(v => !v); setCategoryMsg(''); }}
                  className="text-[9px] font-display font-bold uppercase tracking-wider text-indigo-600 hover:text-indigo-800 flex items-center gap-1"
                >
                  <Tag size={10} /> {showCategoryManager ? 'Done' : 'Manage'}
                </button>
              </div>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 font-medium"
              >
                {categories.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>

            {showCategoryManager && (
              <div className="bg-slate-50 border border-slate-200 rounded-xl p-3 space-y-2.5">
                <p className="text-[9px] text-slate-500 leading-normal">
                  Categories are shared — adding or removing one here updates every terminal.
                </p>

                {categoryMsg && (
                  <p className="text-[10px] text-indigo-700 bg-indigo-50 border border-indigo-100 rounded-lg px-2 py-1.5">
                    {categoryMsg}
                  </p>
                )}

                <div className="flex gap-2">
                  <input
                    type="text"
                    placeholder="New category name"
                    value={newCategory}
                    onChange={(e) => setNewCategory(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') handleAddCategory(e); }}
                    className="flex-1 bg-white border border-slate-200 rounded-lg px-2.5 py-1.5 text-[11px] focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                  <button
                    type="button"
                    onClick={handleAddCategory}
                    className="px-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg text-[10px] font-display font-bold uppercase tracking-wider transition-all"
                  >
                    Add
                  </button>
                </div>

                <div className="flex flex-wrap gap-1.5">
                  {categories.map(c => (
                    <span key={c} className="inline-flex items-center gap-1 bg-white border border-slate-200 rounded-lg pl-2 pr-1 py-1 text-[10px] text-slate-700">
                      {c}
                      <button
                        type="button"
                        onClick={() => handleDeleteCategory(c)}
                        className="text-slate-300 hover:text-rose-600 p-0.5 rounded"
                        title={`Delete ${c}`}
                      >
                        <X size={10} />
                      </button>
                    </span>
                  ))}
                </div>
              </div>
            )}

            <div>
              <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                Description *
              </label>
              <input
                type="text"
                required
                placeholder="e.g. Monthly shop rent for July"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 font-medium"
              />
            </div>

            <div>
              <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                Amount (shs) *
              </label>
              <input
                type="number"
                min="1"
                required
                placeholder="e.g. 250000"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
              />
            </div>

            <button
              type="submit"
              className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-display font-bold text-xs uppercase tracking-wider py-2.5 rounded-xl shadow-md transition-all flex items-center justify-center gap-1.5"
            >
              <Plus size={13} /> Record Expense
            </button>
          </form>

          <p className="text-[10px] text-slate-400 leading-relaxed border-t border-slate-100 pt-3">
            Expenses are operating costs and sit outside the gross-profit figures on the dashboard. Only the top
            manager can delete an entry once it is recorded.
          </p>
        </div>
      </div>
    </div>
  );
};

export default ExpensesView;
