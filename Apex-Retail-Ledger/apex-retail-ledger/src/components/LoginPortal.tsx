import React, { useState } from 'react';
import { UserSession } from '../types';
import localDB from '../utils/localDB';
import { ShieldCheck, Lock, User, Key, ShieldAlert, Coins, Eye, EyeOff } from 'lucide-react';
import { motion } from 'motion/react';

interface LoginPortalProps {
  onLoginSuccess: (session: UserSession) => void;
}

export const LoginPortal: React.FC<LoginPortalProps> = ({ onLoginSuccess }) => {
  const [selectedRole, setSelectedRole] = useState<'worker' | 'manager' | 'top_manager'>('worker');
  const [userId, setUserId] = useState('');
  const [passcode, setPasscode] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [busy, setBusy] = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const trimmedId = userId.trim().toUpperCase();
    const trimmedPass = passcode.trim();

    if (!trimmedId || !trimmedPass) {
      setError('Please fill in both User ID and passcode.');
      return;
    }

    // Pull the authoritative staff directory from Neon first, so we validate
    // against the cloud database rather than a possibly-stale cached PIN.
    // Falls back to whatever is cached locally if the server is unreachable.
    let staffList = localDB.getStaffProfiles();
    setBusy(true);
    try {
      const resp = await fetch('/api/staff');
      if (resp.ok) {
        const data = await resp.json();
        if (data?.success && Array.isArray(data.staff) && data.staff.length > 0) {
          localDB.setStaffProfiles(data.staff);
          staffList = data.staff;
        }
      }
    } catch {
      // offline / unreachable → use local cache
    } finally {
      setBusy(false);
    }

    const matchedStaff = staffList.find(s => s.userId === trimmedId);

    if (!matchedStaff) {
      setError(`No registered staff member found with ID: ${trimmedId}`);
      return;
    }

    // Role check
    if (matchedStaff.role !== selectedRole) {
      setError(`Staff member ${matchedStaff.name} is a ${matchedStaff.role.replace('_', ' ')}. Please select the correct role above.`);
      return;
    }

    // Validate passcode
    if (trimmedPass === matchedStaff.passcode) {
      const session: UserSession = {
        userId: matchedStaff.userId,
        name: matchedStaff.name,
        role: matchedStaff.role
      };
      localDB.setSession(session);
      localDB.logAction(session.userId, session.name, session.role, 'LOGIN', `Shift authenticated successfully as ${session.role.replace('_', ' ')}`);
      onLoginSuccess(session);
    } else {
      setError('Incorrect security passcode.');
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 flex flex-col justify-center items-center px-4 py-12 relative overflow-hidden font-sans">
      {/* Background visual ambiance */}
      <div className="absolute top-1/4 left-1/4 w-96 h-96 rounded-full bg-indigo-900/10 blur-3xl" />
      <div className="absolute bottom-1/4 right-1/4 w-96 h-96 rounded-full bg-emerald-900/10 blur-3xl" />

      <div className="w-full max-w-md bg-slate-900 border border-slate-800 rounded-3xl p-8 shadow-2xl relative z-10">
        {/* Brand identity */}
        <div className="text-center mb-8">
          <div className="inline-flex p-3 bg-gradient-to-tr from-indigo-600 to-violet-600 rounded-2xl text-white shadow-lg mb-3">
            <Coins size={28} />
          </div>
          <h2 className="text-xl font-display font-black text-white tracking-tight uppercase">APEX UNIFIED TERMINAL</h2>
          <p className="text-xs text-slate-400 mt-1.5 leading-relaxed">
            Multi-Device Cashier Interconnect Gateway
          </p>
        </div>

        {/* Role Selector Tabs */}
        <div className="flex bg-slate-950 p-1.5 rounded-xl border border-slate-800 mb-6 gap-1">
          <button
            type="button"
            onClick={() => { setSelectedRole('worker'); setError(null); }}
            className={`flex-1 py-2.5 rounded-lg text-[10px] font-semibold transition-all flex items-center justify-center gap-1.5 ${
              selectedRole === 'worker'
                ? 'bg-emerald-600 text-white shadow-sm font-bold'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <User size={12} />
            Worker
          </button>
          <button
            type="button"
            onClick={() => { setSelectedRole('manager'); setError(null); }}
            className={`flex-1 py-2.5 rounded-lg text-[10px] font-semibold transition-all flex items-center justify-center gap-1.5 ${
              selectedRole === 'manager'
                ? 'bg-indigo-600 text-white shadow-sm font-bold'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <ShieldCheck size={12} />
            Manager
          </button>
          <button
            type="button"
            onClick={() => { setSelectedRole('top_manager'); setError(null); }}
            className={`flex-1 py-2.5 rounded-lg text-[10px] font-semibold transition-all flex items-center justify-center gap-1.5 ${
              selectedRole === 'top_manager'
                ? 'bg-amber-600 text-white shadow-sm font-bold'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <ShieldCheck size={12} className="text-amber-300" />
            Top Manager
          </button>
        </div>

        {/* Credentials Form */}
        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="block text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider mb-1.5">
              Staff ID Credentials
            </label>
            <div className="relative">
              <User className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500" size={16} />
              <input
                type="text"
                placeholder="Enter your staff ID"
                value={userId}
                onChange={(e) => setUserId(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl py-3 pl-11 pr-4 text-sm text-white placeholder-slate-600 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-500 transition-all uppercase font-mono"
              />
            </div>
          </div>

          <div>
            <div className="flex justify-between items-center mb-1.5">
              <label className="block text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider">
                {selectedRole === 'top_manager' 
                  ? 'Top Manager Passcode' 
                  : selectedRole === 'manager' 
                    ? 'Manager Passcode' 
                    : 'Worker PIN Code'}
              </label>
              {(selectedRole === 'manager' || selectedRole === 'top_manager') && (
                <span className={`text-[8px] font-black px-1.5 py-0.5 rounded uppercase tracking-wider ${
                  selectedRole === 'top_manager' ? 'bg-amber-500/20 text-amber-400' : 'bg-indigo-500/10 text-indigo-400'
                }`}>
                  {selectedRole === 'top_manager' ? 'ULTRA PRIVILEGE' : 'HIGH PRIVILEGE'}
                </span>
              )}
            </div>
            <div className="relative">
              <Key className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500" size={16} />
              <input
                type={showPassword ? 'text' : 'password'}
                placeholder={selectedRole === 'top_manager' ? 'Enter Top Manager passcode' : selectedRole === 'manager' ? 'Enter manager passcode' : 'Enter worker PIN'}
                value={passcode}
                onChange={(e) => setPasscode(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl py-3 pl-11 pr-11 text-sm text-white placeholder-slate-600 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-500 transition-all font-mono"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3.5 top-1/2 -translate-y-1/2 text-slate-500 hover:text-white"
              >
                {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>

          {error && (
            <div className="bg-red-500/10 border border-red-500/20 text-red-400 p-3 rounded-xl text-xs flex items-start gap-2.5">
              <ShieldAlert size={16} className="shrink-0 mt-0.5" />
              <span className="font-sans leading-relaxed">{error}</span>
            </div>
          )}

          <button
            type="submit"
            disabled={busy}
            className={`w-full py-3 rounded-xl text-xs font-semibold uppercase tracking-wider transition-all shadow-md flex items-center justify-center gap-2 disabled:opacity-60 ${
              selectedRole === 'top_manager'
                ? 'bg-gradient-to-r from-amber-600 to-amber-500 hover:from-amber-500 hover:to-amber-400 text-white shadow-amber-950/50'
                : selectedRole === 'manager'
                  ? 'bg-gradient-to-r from-indigo-600 to-violet-600 hover:from-indigo-500 hover:to-violet-500 text-white shadow-indigo-950/50'
                  : 'bg-emerald-600 hover:bg-[#10b981] text-white shadow-emerald-950/50'
            }`}
          >
            {busy ? 'Verifying…' : 'Authenticate Shift'}
          </button>
        </form>
      </div>
    </div>
  );
};
