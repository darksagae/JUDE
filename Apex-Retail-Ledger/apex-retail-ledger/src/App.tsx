import { useState, useEffect } from 'react';
import { Product, Sale, UserSession } from './types';
import localDB from './utils/localDB';
import POSView from './components/POSView';
import DashboardView from './components/DashboardView';
import InventoryView from './components/InventoryView';
import AuditLogsView from './components/AuditLogsView';
import StaffSettingsView from './components/StaffSettingsView';
import { LoginPortal } from './components/LoginPortal';
import { SalesLedgerView } from './components/SalesLedgerView';
import { 
  LayoutDashboard, Receipt, Package, ShieldCheck, Users, 
  Wifi, WifiOff, RefreshCw, Clock, Coins, ShieldAlert, Sparkles,
  History, LogOut, Lock, HelpCircle
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';

export default function App() {
  const [currentSession, setCurrentSession] = useState<UserSession>(() => localDB.getSession());
  const [isLocked, setIsLocked] = useState(true); // Always lock terminal on boot for security credentials
  const [activeTab, setActiveTab] = useState<'pos' | 'history' | 'dashboard' | 'inventory' | 'audit' | 'settings'>('pos');
  const [isOffline, setIsOffline] = useState(() => localDB.isOfflineMode());
  const [pendingSyncCount, setPendingSyncCount] = useState(0);
  const [isSyncing, setIsSyncing] = useState(false);
  const [syncStatusMsg, setSyncStatusMsg] = useState<string | null>(null);
  const [lastSyncTime, setLastSyncTime] = useState<string>('Never');

  // Initialize DB & Fetch Unsynced counts
  useEffect(() => {
    localDB.init();
    updatePendingSyncCount();
  }, []);

  // Periodic automatic sync background polling (The Interconnect Engine)
  // Ensures different cashier/teller devices interconnect in near-real-time!
  useEffect(() => {
    if (isOffline || isLocked) return;

    // Trigger initial pull on unlock
    localDB.triggerSync()
      .then(() => {
        updatePendingSyncCount();
        setLastSyncTime(new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }));
      })
      .catch(err => console.log('Initial sync on unlock deferred:', err.message));

    const interval = setInterval(async () => {
      try {
        const res = await localDB.triggerSync();
        updatePendingSyncCount();
        setLastSyncTime(new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }));
      } catch (err) {
        console.log('Background cashier interconnect sync deferred: offline/connecting');
      }
    }, 12000); // Poll every 12 seconds for extremely fast cashier coordination!

    return () => clearInterval(interval);
  }, [isOffline, isLocked]);

  const updatePendingSyncCount = () => {
    const sales = localDB.getSales();
    const unsynced = sales.filter(s => !s.synced).length;
    setPendingSyncCount(unsynced);
  };

  const handleSessionChange = (newSession: UserSession) => {
    setCurrentSession(newSession);
    // If worker, force return to POS or History if they were on a manager-only tab
    if (newSession.role === 'worker' && ['dashboard', 'inventory', 'audit'].includes(activeTab)) {
      setActiveTab('pos');
    }
  };

  const toggleOfflineMode = () => {
    const nextVal = !isOffline;
    localDB.setOfflineMode(nextVal);
    setIsOffline(nextVal);
  };

  const triggerManualSync = async () => {
    if (isOffline) {
      alert("Please turn off Offline Mode to synchronize backups!");
      return;
    }
    setIsSyncing(true);
    setSyncStatusMsg("Initiating master database interconnect sync...");
    
    try {
      await new Promise(resolve => setTimeout(resolve, 800));
      const res = await localDB.triggerSync();
      updatePendingSyncCount();
      setLastSyncTime(new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }));
      
      if (res.syncedCount > 0) {
        setSyncStatusMsg(`Sync Success! Synced ${res.syncedCount} sales & pulled master updates.`);
      } else {
        setSyncStatusMsg("Database synchronized with cloud. All terminals aligned.");
      }
    } catch (err) {
      console.error(err);
      setSyncStatusMsg("Sync Deferred: Server backend unreachable. Offline buffer active.");
    } finally {
      setIsSyncing(false);
      setTimeout(() => setSyncStatusMsg(null), 3000);
    }
  };

  const handleSaleComplete = () => {
    updatePendingSyncCount();
  };

  const handleManagerTabRefresh = () => {
    updatePendingSyncCount();
  };

  const handleLoginSuccess = (session: UserSession) => {
    setCurrentSession(session);
    setIsLocked(false);
    updatePendingSyncCount();
  };

  const handleLockTerminal = () => {
    // Audit log terminal lock
    localDB.logAction(currentSession.userId, currentSession.name, currentSession.role, 'LOGOUT', 'Terminal locked/secured');
    setIsLocked(true);
  };

  const isManager = currentSession.role === 'manager' || currentSession.role === 'top_manager';

  // Render Login Portal if terminal is locked
  if (isLocked) {
    return <LoginPortal onLoginSuccess={handleLoginSuccess} />;
  }

  return (
    <div className={`min-h-screen flex flex-col font-sans transition-colors duration-300 selection:bg-indigo-500/10 ${
      !isManager 
        ? 'bg-[#0B0F19] text-slate-100' // Dark aesthetic for workers (checkout touchscreen design)
        : 'bg-[#f8fafc] text-slate-900' // Light, spacious premium layout for managers
    }`}>
      
      {/* 1. TOP UTILITY HEADER - Terminal Status Panel */}
      <header className={`border-b sticky top-0 z-40 px-6 py-4 flex flex-col md:flex-row justify-between items-start md:items-center gap-4 transition-colors duration-300 ${
        !isManager 
          ? 'bg-[#111827]/90 border-slate-800 backdrop-blur-md text-white' 
          : 'bg-white border-slate-200 text-slate-800 shadow-sm'
      }`}>
        <div className="flex items-center gap-3">
          <div className={`p-2.5 rounded-xl text-white shadow-md transition-all ${
            !isManager ? 'bg-emerald-600 shadow-emerald-950/20' : 'bg-indigo-600 shadow-indigo-200'
          }`}>
            <Coins size={18} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className={`font-display font-black text-lg tracking-tight uppercase ${!isManager ? 'text-white' : 'text-slate-900'}`}>
                APEX RETAIL
              </h1>
              <span className={`text-[9px] font-mono font-bold px-2 py-0.5 rounded ${
                !isManager ? 'bg-emerald-500/10 text-emerald-400' : 'bg-indigo-50 text-indigo-700'
              }`}>
                {!isManager ? 'Checkout Station' : 'Supervisor Portal'}
              </span>
            </div>
            <p className={`text-[10px] font-mono tracking-wider ${!isManager ? 'text-slate-400' : 'text-slate-500'}`}>
              INTERCONNECT: ACTIVE &bull; TERMINAL ID: {currentSession.userId}
            </p>
          </div>
        </div>

        {/* Sync Controls and Account Status Widget */}
        <div className="flex flex-wrap items-center gap-3.5 w-full md:w-auto">
          
          {/* Last Synced status indicator */}
          <div className={`text-[10px] font-mono px-3 py-1.5 rounded-xl border flex items-center gap-1.5 ${
            !isManager ? 'bg-slate-950/40 border-slate-800 text-slate-400' : 'bg-slate-50 border-slate-200 text-slate-500'
          }`}>
            <span className="h-1.5 w-1.5 rounded-full bg-indigo-500 animate-pulse" />
            <span>Synced: <strong className={!isManager ? 'text-slate-200' : 'text-slate-700'}>{lastSyncTime}</strong></span>
          </div>

          {/* Offline Mode Toggle Switch */}
          <div className={`flex items-center gap-2 px-3 py-1.5 rounded-xl border ${
            !isManager ? 'bg-slate-950/40 border-slate-800' : 'bg-slate-50 border-slate-200'
          }`}>
            {isOffline ? (
              <WifiOff size={13} className="text-amber-500 animate-pulse" />
            ) : (
              <Wifi size={13} className="text-green-500" />
            )}
            <span className={`text-[10px] font-mono font-semibold uppercase ${!isManager ? 'text-slate-300' : 'text-slate-600'}`}>
              {isOffline ? 'Offline Cache' : 'Interconnected'}
            </span>
            <button
              onClick={toggleOfflineMode}
              className={`w-8 h-4 rounded-full p-0.5 transition-all ${
                isOffline ? 'bg-amber-500' : 'bg-slate-300'
              }`}
            >
              <div 
                className={`w-3 h-3 bg-white rounded-full transition-all ${
                  isOffline ? 'translate-x-4' : 'translate-x-0'
                }`}
              />
            </button>
          </div>

          {/* Pending Sync Backup Widget */}
          <div className={`flex items-center gap-2.5 px-3.5 py-1.5 rounded-xl border text-[10px] font-mono ${
            !isManager ? 'bg-slate-950/40 border-slate-800 text-slate-300' : 'bg-slate-50 border-slate-200 text-slate-600'
          }`}>
            <span>Queued:</span>
            <span className={`font-bold px-1.5 py-0.5 rounded ${
              pendingSyncCount > 0 ? 'bg-amber-500/20 text-amber-400 font-black' : 'bg-green-500/10 text-green-400'
            }`}>
              {pendingSyncCount}
            </span>
            
            <button
              onClick={triggerManualSync}
              disabled={isSyncing}
              className={`p-1 hover:bg-slate-800/20 rounded transition-all ${
                isSyncing ? 'animate-spin text-indigo-400' : 'text-slate-400 hover:text-white'
              }`}
              title="Force Database Sync Backup"
            >
              <RefreshCw size={11} />
            </button>
          </div>

          {/* Current Staff Shift badge & Lock/Logout Button */}
          <div className={`px-3.5 py-1.5 rounded-xl border flex items-center gap-2.5 text-[10px] ${
            !isManager ? 'bg-slate-950/40 border-slate-800 text-slate-300' : 'bg-slate-50 border-slate-200 text-slate-700'
          }`}>
            <div className={`h-2 w-2 rounded-full ${isManager ? 'bg-indigo-500 animate-pulse' : 'bg-emerald-500 animate-pulse'}`} />
            <span className={`font-semibold truncate max-w-[100px] ${!isManager ? 'text-slate-100' : 'text-slate-900'}`}>{currentSession.name}</span>
            <span className={`font-extrabold px-1.5 py-0.5 rounded-[5px] text-[8px] uppercase tracking-wider ${
              isManager ? 'bg-indigo-100 text-indigo-800' : 'bg-emerald-950 text-emerald-400'
            }`}>{currentSession.role}</span>
            
            <button
              onClick={handleLockTerminal}
              className="px-2 py-1 bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 hover:text-rose-300 rounded-lg transition-all flex items-center gap-1.5 font-bold uppercase tracking-wider text-[9px]"
              title="Lock Terminal / Log Out Shift"
            >
              <LogOut size={11} className="shrink-0 text-rose-500" />
              <span>Log Out</span>
            </button>
          </div>
        </div>
      </header>

      {/* Sync State Banner Notification */}
      <AnimatePresence>
        {syncStatusMsg && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className={`px-6 py-2 text-center text-[11px] font-mono font-medium flex items-center justify-center gap-2 border-b ${
              !isManager 
                ? 'bg-indigo-950/40 border-indigo-900 text-indigo-300' 
                : 'bg-indigo-50 border-indigo-100 text-indigo-700'
            }`}
          >
            <span className="flex h-1.5 w-1.5 rounded-full bg-indigo-500 animate-ping" />
            {syncStatusMsg}
          </motion.div>
        )}
      </AnimatePresence>

      {/* 2. MAIN SYSTEM CONTENT */}
      <div className="flex-1 flex flex-col md:flex-row">
        
        {/* Navigation Rail Sidebar */}
        <nav className={`w-full md:w-60 border-r p-4 space-y-1.5 shrink-0 flex flex-row md:flex-col overflow-x-auto md:overflow-x-visible transition-colors duration-300 ${
          !isManager 
            ? 'bg-[#111827] border-slate-800 text-slate-300' 
            : 'bg-white border-slate-200 text-slate-600'
        }`}>
          {/* Rail Header */}
          <div className="hidden md:block py-3 px-3.5">
            <span className={`text-[10px] font-display font-extrabold uppercase tracking-wider ${
              !isManager ? 'text-slate-500' : 'text-slate-400'
            }`}>
              Shift Modules
            </span>
          </div>

          {/* POS tab */}
          <button
            onClick={() => setActiveTab('pos')}
            className={`w-full flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-display font-semibold transition-all ${
              activeTab === 'pos'
                ? !isManager 
                  ? 'bg-emerald-600 text-white shadow-md font-bold shadow-emerald-950/20' 
                  : 'bg-indigo-600 text-white shadow-md font-bold'
                : !isManager
                  ? 'text-slate-300 hover:text-emerald-400 hover:bg-slate-900'
                  : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
            }`}
          >
            <Receipt size={16} />
            POS Terminal
          </button>

          {/* Sales History tab (Accessible by BOTH worker and manager!) */}
          <button
            onClick={() => setActiveTab('history')}
            className={`w-full flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-display font-semibold transition-all ${
              activeTab === 'history'
                ? !isManager 
                  ? 'bg-emerald-600 text-white shadow-md font-bold shadow-emerald-950/20' 
                  : 'bg-indigo-600 text-white shadow-md font-bold'
                : !isManager
                  ? 'text-slate-300 hover:text-emerald-400 hover:bg-slate-900'
                  : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
            }`}
          >
            <History size={16} />
            Sales Ledger
          </button>

          {/* Dashboard tab */}
          <button
            onClick={() => setActiveTab('dashboard')}
            className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-display font-semibold transition-all ${
              activeTab === 'dashboard'
                ? !isManager 
                  ? 'bg-indigo-600 text-white shadow-md font-bold' 
                  : 'bg-indigo-600 text-white shadow-md font-bold'
                : !isManager
                  ? 'text-slate-500 opacity-60 hover:text-indigo-400'
                  : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
            }`}
          >
            <div className="flex items-center gap-3">
              <LayoutDashboard size={16} />
              <span>Manager Stats</span>
            </div>
            {!isManager && <Lock size={12} className="text-slate-500" />}
          </button>

          {/* Inventory tab */}
          <button
            onClick={() => setActiveTab('inventory')}
            className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-display font-semibold transition-all ${
              activeTab === 'inventory'
                ? !isManager 
                  ? 'bg-indigo-600 text-white shadow-md font-bold' 
                  : 'bg-indigo-600 text-white shadow-md font-bold'
                : !isManager
                  ? 'text-slate-500 opacity-60 hover:text-indigo-400'
                  : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
            }`}
          >
            <div className="flex items-center gap-3">
              <Package size={16} />
              <span>Inventory</span>
            </div>
            {!isManager && <Lock size={12} className="text-slate-500" />}
          </button>

          {/* Audit logs tab */}
          <button
            onClick={() => setActiveTab('audit')}
            className={`w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-display font-semibold transition-all ${
              activeTab === 'audit'
                ? !isManager 
                  ? 'bg-indigo-600 text-white shadow-md font-bold' 
                  : 'bg-indigo-600 text-white shadow-md font-bold'
                : !isManager
                  ? 'text-slate-500 opacity-60 hover:text-indigo-400'
                  : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
            }`}
          >
            <div className="flex items-center gap-3">
              <ShieldCheck size={16} />
              <span>Audit Ledger</span>
            </div>
            {!isManager && <Lock size={12} className="text-slate-500" />}
          </button>

          <div className={`hidden md:block border-t my-4 ${!isManager ? 'border-slate-800' : 'border-slate-100'}`}></div>

          {/* Settings / Switch tab */}
          <button
            onClick={() => setActiveTab('settings')}
            className={`w-full flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-display font-semibold transition-all ${
              activeTab === 'settings'
                ? !isManager 
                  ? 'bg-emerald-600 text-white shadow-md font-bold shadow-emerald-950/20' 
                  : 'bg-indigo-600 text-white shadow-md font-bold'
                : !isManager
                  ? 'text-slate-300 hover:text-emerald-400 hover:bg-slate-900'
                  : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
            }`}
          >
            <Users size={16} />
            Staff Shifts
          </button>

          <div className="md:mt-auto pt-2 md:pt-0"></div>
          
          {/* Explicit Log Out button for all accounts */}
          <button
            onClick={handleLockTerminal}
            className={`flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-xs font-display font-bold transition-all text-rose-500 hover:bg-rose-500/10 shrink-0 w-auto md:w-full`}
            title="Log out of session and lock terminal"
          >
            <LogOut size={16} className="text-rose-500 shrink-0" />
            <span>Log Out Shift</span>
          </button>
        </nav>

        {/* Dynamic App Workspace Viewport */}
        <main className={`flex-1 p-6 md:p-8 overflow-y-auto max-w-full ${
          !isManager ? 'bg-[#0B0F19]' : 'bg-[#f8fafc]'
        }`}>
          {activeTab === 'pos' && (
            <POSView onSaleComplete={handleSaleComplete} />
          )}

          {activeTab === 'history' && (
            <SalesLedgerView role={currentSession.role} onRefresh={handleManagerTabRefresh} />
          )}

          {activeTab === 'dashboard' && (
            isManager ? (
              <DashboardView onRefresh={handleManagerTabRefresh} />
            ) : (
              <div className="h-full max-w-md mx-auto flex flex-col items-center justify-center text-center py-24 space-y-4">
                <div className="p-4 bg-slate-900 border border-slate-800 text-indigo-400 rounded-full">
                  <ShieldAlert size={32} />
                </div>
                <h3 className="font-display font-extrabold text-white text-base">Authorized Access Only</h3>
                <p className="text-xs text-slate-400 leading-relaxed font-sans">
                  The executive analytical profit & loss reports dashboard is locked for worker shifts. Please request supervisor credentials to switch roles.
                </p>
                <button
                  onClick={() => setActiveTab('settings')}
                  className="bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl px-5 py-2 text-xs font-display font-bold uppercase transition-all shadow-md shadow-emerald-950/30"
                >
                  Switch Shift
                </button>
              </div>
            )
          )}

          {activeTab === 'inventory' && (
            isManager ? (
              <InventoryView onRefresh={handleManagerTabRefresh} />
            ) : (
              <div className="h-full max-w-md mx-auto flex flex-col items-center justify-center text-center py-24 space-y-4">
                <div className="p-4 bg-slate-900 border border-slate-800 text-indigo-400 rounded-full">
                  <ShieldAlert size={32} />
                </div>
                <h3 className="font-display font-extrabold text-white text-base">Authorized Access Only</h3>
                <p className="text-xs text-slate-400 leading-relaxed font-sans">
                  The commodity manager ledger and restock forms are strictly restricted to manager permissions.
                </p>
                <button
                  onClick={() => setActiveTab('settings')}
                  className="bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl px-5 py-2 text-xs font-display font-bold uppercase transition-all shadow-md shadow-emerald-950/30"
                >
                  Switch Shift
                </button>
              </div>
            )
          )}

          {activeTab === 'audit' && (
            isManager ? (
              <AuditLogsView />
            ) : (
              <div className="h-full max-w-md mx-auto flex flex-col items-center justify-center text-center py-24 space-y-4">
                <div className="p-4 bg-slate-900 border border-slate-800 text-indigo-400 rounded-full">
                  <ShieldAlert size={32} />
                </div>
                <h3 className="font-display font-extrabold text-white text-base">Authorized Access Only</h3>
                <p className="text-xs text-slate-400 leading-relaxed font-sans">
                  The detailed audit log ledger containing shift trails is restricted to security supervisors.
                </p>
                <button
                  onClick={() => setActiveTab('settings')}
                  className="bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl px-5 py-2 text-xs font-display font-bold uppercase transition-all shadow-md shadow-emerald-950/30"
                >
                  Switch Shift
                </button>
              </div>
            )
          )}

          {activeTab === 'settings' && (
            <StaffSettingsView onSessionChange={handleSessionChange} />
          )}
        </main>
      </div>

      {/* 3. FOOTER */}
      <footer className={`border-t px-6 py-3.5 text-center text-[10px] flex flex-col sm:flex-row justify-between items-center gap-2 transition-colors duration-300 ${
        !isManager 
          ? 'bg-[#111827] border-slate-800/80 text-slate-400' 
          : 'bg-white border-slate-200 text-slate-500'
      }`}>
        <p className="font-sans">APEX LEDGER SYSTEM &bull; Real-time Offline Synchronization Active</p>
        <p className={`font-mono text-[9px] uppercase tracking-wider px-2 py-0.5 rounded border ${
          !isManager 
            ? 'bg-slate-950/50 border-slate-800 text-emerald-400' 
            : 'bg-slate-100 border-slate-200 text-slate-700'
        }`}>
          SYSTEM LEVEL TERMINAL OK
        </p>
      </footer>
    </div>
  );
}
