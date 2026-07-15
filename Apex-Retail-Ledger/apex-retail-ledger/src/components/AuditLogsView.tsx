import React, { useState, useMemo } from 'react';
import { AuditLog } from '../types';
import localDB from '../utils/localDB';
import { ShieldCheck, Search, Filter, Trash2 } from 'lucide-react';

export const AuditLogsView: React.FC = () => {
  const [logs, setLogs] = useState<AuditLog[]>(() => localDB.getAuditLogs());
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedType, setSelectedType] = useState('All');

  const actionTypes = useMemo(() => {
    const types = new Set(logs.map(l => l.actionType));
    return ['All', ...Array.from(types)];
  }, [logs]);

  const filteredLogs = useMemo(() => {
    return logs.filter(l => {
      const matchesSearch = l.userName.toLowerCase().includes(searchQuery.toLowerCase()) || 
                            l.details.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesType = selectedType === 'All' || l.actionType === selectedType;
      return matchesSearch && matchesType;
    });
  }, [logs, searchQuery, selectedType]);

  const handleClearLogs = () => {
    if (confirm("Are you sure you want to clear audit logs history?")) {
      localStorage.setItem('sm_audit_logs', JSON.stringify([]));
      setLogs([]);
    }
  };

  return (
    <div className="bg-white rounded-2xl border border-slate-100 shadow-sm p-6 space-y-6">
      {/* Search & Filters */}
      <div className="flex flex-col md:flex-row gap-4 items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="p-2 bg-emerald-50 text-emerald-600 rounded-xl">
            <ShieldCheck size={18} />
          </div>
          <div>
            <h3 className="font-display font-semibold text-slate-800 text-sm">Detailed Audit Ledger</h3>
            <p className="text-xs text-slate-400">Chronological history of transactions, login events, and stock actions</p>
          </div>
        </div>

        {logs.length > 0 && (
          <button
            onClick={handleClearLogs}
            className="text-xs font-display font-semibold text-red-500 hover:text-red-600 flex items-center gap-1 transition-colors"
          >
            <Trash2 size={13} />
            Purge History
          </button>
        )}
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
          <input
            type="text"
            placeholder="Search logs by staff name or action details..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 rounded-xl py-2 pl-10 pr-4 text-xs font-sans placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-sky-500/20 focus:border-sky-500 text-slate-800"
          />
        </div>
        <div className="flex gap-1 overflow-x-auto pb-1 max-w-full no-scrollbar">
          {actionTypes.map(type => (
            <button
              key={type}
              onClick={() => setSelectedType(type)}
              className={`px-3 py-1.5 rounded-xl text-[10px] font-display font-semibold whitespace-nowrap border transition-all ${
                selectedType === type
                  ? 'bg-slate-900 border-slate-900 text-white shadow-sm'
                  : 'bg-white border-slate-200 hover:bg-slate-50 text-slate-600'
              }`}
            >
              {type}
            </button>
          ))}
        </div>
      </div>

      {/* Log Feed */}
      <div className="overflow-x-auto border border-slate-100 rounded-xl">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-slate-50 text-slate-400 font-display font-bold text-[10px] tracking-wider uppercase border-b border-slate-100">
              <th className="py-4 px-5">Timestamp</th>
              <th className="py-4 px-5">Staff Identity</th>
              <th className="py-4 px-5">Event Category</th>
              <th className="py-4 px-5">Action Description</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 text-slate-700 text-xs font-medium">
            {filteredLogs.map(log => {
              const isManager = log.userRole === 'manager';

              return (
                <tr key={log.id} className="hover:bg-slate-50/50 transition-colors">
                  <td className="py-4.5 px-5 font-mono text-[10px] text-slate-400">
                    {new Date(log.timestamp).toLocaleString()}
                  </td>
                  <td className="py-4.5 px-5">
                    <div className="flex flex-col">
                      <span className="font-display font-semibold text-slate-800">{log.userName}</span>
                      <span className={`text-[9px] font-display font-bold uppercase mt-0.5 tracking-wider ${
                        isManager ? 'text-amber-600' : 'text-slate-400'
                      }`}>
                        {log.userRole}
                      </span>
                    </div>
                  </td>
                  <td className="py-4.5 px-5">
                    <span className={`font-mono font-bold text-[9px] px-2 py-0.5 rounded-md ${
                      log.actionType === 'LOGIN' ? 'bg-purple-50 text-purple-700 border border-purple-100' :
                      log.actionType === 'SALE' ? 'bg-emerald-50 text-emerald-700 border border-emerald-100' :
                      log.actionType === 'STOCK_IN' ? 'bg-amber-50 text-amber-700 border border-amber-100' :
                      log.actionType === 'SYNC' ? 'bg-sky-50 text-sky-700 border border-sky-100' :
                      'bg-slate-50 text-slate-700 border border-slate-200/50'
                    }`}>
                      {log.actionType}
                    </span>
                  </td>
                  <td className="py-4.5 px-5 text-slate-600 font-sans font-medium">
                    {log.details}
                  </td>
                </tr>
              );
            })}

            {filteredLogs.length === 0 && (
              <tr>
                <td colSpan={4} className="py-12 text-center text-slate-400 font-display text-sm">
                  No actions logged under current criteria
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};
export default AuditLogsView;
