import React, { useState } from 'react';
import { UserSession } from '../types';
import { localDB } from '../utils/localDB';
import { hardwareManager } from '../utils/hardware';
import { 
  ShieldAlert, 
  ShieldCheck, 
  User, 
  Check, 
  Lock, 
  Unlock, 
  Key, 
  Eye, 
  EyeOff, 
  Trash2, 
  UserPlus, 
  Sliders, 
  X, 
  CornerDownRight,
  RefreshCw,
  LogIn,
  Printer,
  Wifi,
  Bluetooth
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';

interface StaffSettingsViewProps {
  onSessionChange: (session: UserSession) => void;
}

export const StaffSettingsView: React.FC<StaffSettingsViewProps> = ({ onSessionChange }) => {
  const [currentSession, setCurrentSession] = useState<UserSession>(() => localDB.getSession());
  const [staff, setStaff] = useState<any[]>(() => localDB.getStaffProfiles());

  // Create Staff Form States
  const [newName, setNewName] = useState('');
  const [newRole, setNewRole] = useState<'manager' | 'worker'>('worker');
  const [newPasscode, setNewPasscode] = useState('');
  const [newCustomId, setNewCustomId] = useState('');
  const [formError, setFormError] = useState('');
  const [formSuccess, setFormSuccess] = useState('');

  // Password / PIN Visibility
  const [visiblePasscodes, setVisiblePasscodes] = useState<Record<string, boolean>>({});

  // Self-service account edit states ("My Account" — every role, including top manager)
  const [selfName, setSelfName] = useState(() => localDB.getSession().name);
  const [selfId, setSelfId] = useState(() => localDB.getSession().userId);
  const [workerCurrentPass, setWorkerCurrentPass] = useState('');
  const [workerNewPass, setWorkerNewPass] = useState('');
  const [workerConfirmPass, setWorkerConfirmPass] = useState('');
  const [workerPassSuccess, setWorkerPassSuccess] = useState('');
  const [workerPassError, setWorkerPassError] = useState('');

  // Printer settings states
  const [showPrinterModal, setShowPrinterModal] = useState(false);
  const [paperWidth, setPaperWidth] = useState<'58mm' | '80mm'>(() => localDB.getPrinterSettings().paperWidth);
  const [defaultFormat, setDefaultFormat] = useState<'receipt' | 'sticker'>(() => localDB.getPrinterSettings().defaultFormat);
  const [ipAddress, setIpAddress] = useState(() => localDB.getPrinterSettings().ipAddress);
  const [bluetoothAddress, setBluetoothAddress] = useState(() => localDB.getPrinterSettings().bluetoothAddress);
  const [modalSuccess, setModalSuccess] = useState('');
  const [modalError, setModalError] = useState('');

  const isTopManager = currentSession.role === 'top_manager';
  const isManager = currentSession.role === 'manager';
  const isWorker = currentSession.role === 'worker';

  const handleTogglePasscodeVisibility = (userId: string) => {
    setVisiblePasscodes(prev => ({ ...prev, [userId]: !prev[userId] }));
  };

  // Switch / Impersonate user profile directly
  const handleImpersonate = (targetUser: any) => {
    // Top Manager can open all accounts. Manager can only open worker accounts.
    if (isTopManager || (isManager && targetUser.role === 'worker')) {
      const session: UserSession = {
        userId: targetUser.userId,
        name: targetUser.name,
        role: targetUser.role
      };
      localDB.setSession(session);
      setCurrentSession(session);
      onSessionChange(session);
      
      // Update local state
      localDB.logAction(
        currentSession.userId,
        currentSession.name,
        currentSession.role,
        'IMPERSONATE',
        `Direct session shift opened for user: ${targetUser.name} (ID: ${targetUser.userId})`
      );
    }
  };

  // Create standard user passcode or manager passcode
  const handleCreateStaff = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError('');
    setFormSuccess('');

    const cleanName = newName.trim();
    const cleanPass = newPasscode.trim();
    const cleanId = newCustomId.trim().toUpperCase();

    if (!cleanName || !cleanPass) {
      setFormError('Name and passcode are required.');
      return;
    }

    // Role safety: Standard managers can ONLY add workers.
    const resolvedRole = isTopManager ? newRole : 'worker';

    // Generate custom ID if not provided
    let finalId = cleanId;
    if (!finalId) {
      const prefix = resolvedRole === 'manager' ? 'M' : 'W';
      const randNum = Math.floor(100 + Math.random() * 899);
      finalId = `${prefix}${randNum}`;
    }

    // Verify uniqueness
    if (staff.some(s => s.userId === finalId)) {
      setFormError(`A staff member with ID ${finalId} already exists.`);
      return;
    }

    const newStaffMember = {
      userId: finalId,
      name: cleanName,
      role: resolvedRole,
      passcode: cleanPass
    };

    const updatedStaff = [...staff, newStaffMember];
    localDB.setStaffProfiles(updatedStaff);
    setStaff(updatedStaff);

    // Audit Log
    localDB.logAction(
      currentSession.userId,
      currentSession.name,
      currentSession.role,
      'STAFF_ADD',
      `Registered new ${resolvedRole} account: ${cleanName} (ID: ${finalId})`
    );

    setFormSuccess(`Successfully registered ${cleanName} (${finalId})!`);
    setNewName('');
    setNewPasscode('');
    setNewCustomId('');
  };

  // Toggle role between Worker and Manager (Top Manager only privilege)
  const handleToggleRole = (targetUserId: string) => {
    if (!isTopManager) return;

    const targetUser = staff.find(s => s.userId === targetUserId);
    if (!targetUser) return;
    if (targetUser.role === 'top_manager') return; // Cannot toggle top manager

    const newRole = targetUser.role === 'manager' ? 'worker' : 'manager';
    const updatedStaff = staff.map(s => {
      if (s.userId === targetUserId) {
        return { ...s, role: newRole };
      }
      return s;
    });

    localDB.setStaffProfiles(updatedStaff);
    setStaff(updatedStaff);

    // Audit Log
    localDB.logAction(
      currentSession.userId,
      currentSession.name,
      currentSession.role,
      'STAFF_ROLE_CHANGE',
      `Toggled role of ${targetUser.name} (${targetUser.userId}) to ${newRole}`
    );
  };

  // Delete staff member (Top Manager only privilege)
  const handleDeleteStaff = (targetUserId: string) => {
    if (!isTopManager) return;
    const targetUser = staff.find(s => s.userId === targetUserId);
    if (!targetUser) return;
    if (targetUser.role === 'top_manager') return; // Cannot delete top manager

    if (window.confirm(`Are you sure you want to remove staff member ${targetUser.name}?`)) {
      const updatedStaff = staff.filter(s => s.userId !== targetUserId);
      localDB.setStaffProfiles(updatedStaff);
      setStaff(updatedStaff);

      localDB.logAction(
        currentSession.userId,
        currentSession.name,
        currentSession.role,
        'STAFF_REMOVE',
        `Removed staff profile of ${targetUser.name} (${targetUser.userId})`
      );
    }
  };

  // Self-service account update — any role edits their own name, ID and PIN.
  // The current PIN must be re-entered so a walk-up on an unlocked terminal cannot
  // silently take the account over. A blank new PIN simply leaves the PIN unchanged.
  const handleUpdateMyAccount = (e: React.FormEvent) => {
    e.preventDefault();
    setWorkerPassSuccess('');
    setWorkerPassError('');

    const currentProfile = staff.find(s => s.userId === currentSession.userId);
    if (!currentProfile) {
      setWorkerPassError('Your profile could not be found in the staff directory.');
      return;
    }

    if (workerCurrentPass !== currentProfile.passcode) {
      setWorkerPassError('Incorrect current passcode.');
      return;
    }

    const cleanName = selfName.trim();
    const cleanId = selfId.trim().toUpperCase();

    if (!cleanName) {
      setWorkerPassError('Your name cannot be empty.');
      return;
    }
    if (!cleanId) {
      setWorkerPassError('Your staff ID cannot be empty.');
      return;
    }
    if (cleanId !== currentSession.userId && staff.some(s => s.userId === cleanId)) {
      setWorkerPassError(`Staff ID ${cleanId} is already taken by another account.`);
      return;
    }

    const wantsNewPass = workerNewPass.trim().length > 0;
    if (wantsNewPass && workerNewPass !== workerConfirmPass) {
      setWorkerPassError('Confirm passcode does not match.');
      return;
    }

    const updatedStaff = staff.map(s =>
      s.userId === currentSession.userId
        ? {
            ...s,
            userId: cleanId,
            name: cleanName,
            passcode: wantsNewPass ? workerNewPass.trim() : s.passcode
          }
        : s
    );

    localDB.setStaffProfiles(updatedStaff);
    setStaff(updatedStaff);

    const changes = [
      cleanName !== currentSession.name ? 'name' : null,
      cleanId !== currentSession.userId ? 'staff ID' : null,
      wantsNewPass ? 'passcode' : null
    ].filter(Boolean);

    localDB.logAction(
      currentSession.userId,
      currentSession.name,
      currentSession.role,
      'PROFILE_UPDATE',
      changes.length
        ? `Updated own ${changes.join(', ')}${cleanId !== currentSession.userId ? ` (now ${cleanId})` : ''}`
        : 'Re-saved own profile with no changes'
    );

    // Carry the session over so the header, audit trail and future sales use the new identity.
    const nextSession: UserSession = { userId: cleanId, name: cleanName, role: currentSession.role };
    localDB.setSession(nextSession);
    setCurrentSession(nextSession);
    onSessionChange(nextSession);

    setWorkerPassSuccess(changes.length ? 'Your account details have been updated.' : 'No changes to save.');
    setWorkerCurrentPass('');
    setWorkerNewPass('');
    setWorkerConfirmPass('');
  };

  // Save printer settings
  const handleSavePrinterSettings = () => {
    setModalSuccess('');
    setModalError('');

    const cleanIp = ipAddress.trim();
    if (cleanIp && !/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.test(cleanIp)) {
      setModalError('Please enter a valid IPv4 network address (e.g. 192.168.1.100).');
      return;
    }

    const settings = {
      paperWidth,
      defaultFormat,
      ipAddress: cleanIp,
      bluetoothAddress: bluetoothAddress.trim()
    };

    localDB.setPrinterSettings(settings);

    // Update active paired configuration in memory/storage
    if (cleanIp) {
      hardwareManager.pairNetworkPrinter(cleanIp).catch(() => {});
    } else if (bluetoothAddress.trim()) {
      hardwareManager.pairBluetoothPrinter(bluetoothAddress.trim()).catch(() => {});
    }

    localDB.logAction(
      currentSession.userId,
      currentSession.name,
      currentSession.role,
      'PRINTER_CONFIG_SET',
      `Printer settings updated: paperWidth=${paperWidth}, format=${defaultFormat}, ip=${cleanIp || 'None'}, bt=${bluetoothAddress || 'None'}`
    );

    setModalSuccess('Printer hardware settings applied successfully!');
    setTimeout(() => {
      setModalSuccess('');
      setShowPrinterModal(false);
    }, 1500);
  };

  // Trigger test page print
  const handleTestPrint = async () => {
    setModalSuccess('');
    setModalError('');

    try {
      const settings = {
        paperWidth,
        defaultFormat,
        ipAddress: ipAddress.trim(),
        bluetoothAddress: bluetoothAddress.trim()
      };

      const bytes = hardwareManager.generateTestBytes(settings);
      
      const hasDirectPrinter = hardwareManager.getPairedPrinter();
      if (hasDirectPrinter) {
        setModalSuccess('Transmitting raw ESC/POS test pattern stream to hardware connection...');
        await hardwareManager.printRawESCPOS(bytes);
      } else {
        setModalSuccess('Simulated hardware stream triggered. Opening browser document print dialog...');
        window.print();
      }
    } catch (err: any) {
      setModalError(`Hardware communication failed: ${err.message}`);
    }
  };

  const printerSettings = localDB.getPrinterSettings();

  return (
    <div className="grid grid-cols-1 xl:grid-cols-12 gap-6 items-start relative font-sans">
      
      {/* LEFT OR MAIN: Active Staff Directory */}
      <div className="xl:col-span-8 space-y-6">
        
        {/* Top Active Account Header Card */}
        <div className="bg-slate-900 border border-slate-800 text-white rounded-2xl p-6 shadow-md relative overflow-hidden">
          <div className="absolute right-0 top-0 translate-x-12 -translate-y-12 w-48 h-48 bg-indigo-500/10 rounded-full blur-2xl" />
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
            <div className="flex items-center gap-3.5">
              <div className={`p-3 rounded-xl ${
                isTopManager ? 'bg-amber-500/20 text-amber-400' : isManager ? 'bg-indigo-500/20 text-indigo-400' : 'bg-emerald-500/20 text-emerald-400'
              }`}>
                {isTopManager ? <ShieldCheck size={28} /> : <User size={28} />}
              </div>
              <div>
                <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-slate-400">
                  Current Session Shift
                </span>
                <h2 className="text-lg font-display font-black text-white leading-tight uppercase flex items-center gap-2">
                  {currentSession.name}
                  <span className="text-xs text-slate-500 font-mono">({currentSession.userId})</span>
                </h2>
                <span className={`inline-flex items-center gap-1 mt-1 text-[10px] px-2.5 py-0.5 rounded-full font-bold uppercase tracking-wider ${
                  isTopManager ? 'bg-amber-600 text-white' : isManager ? 'bg-indigo-600 text-white' : 'bg-emerald-600 text-white'
                }`}>
                  {isTopManager ? 'Top Manager (Super Admin)' : isManager ? 'Manager (Supervisor)' : 'Worker (Cashier)'}
                </span>
              </div>
            </div>

            <div className="flex flex-col text-left sm:text-right text-xs text-slate-400">
              <span className="font-mono text-[10px]">OPERATIONAL LEVEL</span>
              <span className="text-white font-semibold mt-1">
                {isTopManager ? 'All Access & Accounts Supervisor' : isManager ? 'Restricted Supervisor Dashboard' : 'Standard Sales Checkout POS'}
              </span>
            </div>
          </div>
        </div>

        {/* Staff Management Directory List */}
        <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm space-y-5">
          <div className="flex justify-between items-center">
            <div>
              <h3 className="font-display font-bold text-slate-900 text-sm">Supermarket Staff Directory</h3>
              <p className="text-xs text-slate-400 mt-0.5">View accounts, access levels, passwords, and shift controls</p>
            </div>
            <span className="text-[10px] font-mono bg-slate-100 text-slate-500 px-2 py-1 rounded font-bold uppercase">
              {staff.length} Active Accounts
            </span>
          </div>

          <div className="divide-y divide-slate-100 border border-slate-100 rounded-xl overflow-hidden bg-slate-50/50">
            {staff.map(member => {
              const isSelf = member.userId === currentSession.userId;
              const isTargetTopManager = member.role === 'top_manager';
              const isTargetManager = member.role === 'manager';
              const isTargetWorker = member.role === 'worker';

              // Privilege boundary checks for password visibility
              // Top manager can see ALL. Manager can see standard WORKER passwords. Workers cannot see any other.
              const canSeePasscode = isTopManager || (isManager && isTargetWorker) || isSelf;

              // Privilege checks for direct account login (impersonation)
              // Top manager can open all accounts. Manager can open worker accounts.
              const canImpersonate = !isSelf && (isTopManager || (isManager && isTargetWorker));

              // Privilege checks for role adjustments
              // Top manager can toggle role for other managers and workers.
              const canModifyRole = isTopManager && !isTargetTopManager;

              // Privilege checks for profile deletion
              const canDelete = isTopManager && !isTargetTopManager;

              return (
                <div key={member.userId} className="p-4 bg-white flex flex-col md:flex-row items-start md:items-center justify-between gap-4 hover:bg-slate-50/40 transition-colors">
                  
                  {/* Staff Info Column */}
                  <div className="flex items-center gap-3.5 min-w-[200px]">
                    <div className={`p-2.5 rounded-xl shrink-0 ${
                      isTargetTopManager ? 'bg-amber-50 text-amber-600' : isTargetManager ? 'bg-indigo-50 text-indigo-600' : 'bg-emerald-50 text-emerald-600'
                    }`}>
                      {isTargetTopManager ? <ShieldCheck size={18} /> : <User size={18} />}
                    </div>
                    <div>
                      <h4 className="font-display font-semibold text-xs text-slate-900 flex items-center gap-1.5">
                        {member.name}
                        {isSelf && (
                          <span className="bg-slate-100 text-slate-600 text-[8px] font-black uppercase px-1.5 py-0.5 rounded tracking-wide">
                            YOU
                          </span>
                        )}
                      </h4>
                      <p className="text-[10px] font-mono text-slate-400 mt-0.5">
                        ID: <span className="font-bold text-slate-600">{member.userId}</span> &bull; 
                        <span className="ml-1 uppercase font-bold text-slate-500"> {member.role.replace('_', ' ')}</span>
                      </p>
                    </div>
                  </div>

                  {/* Password Monitoring (Secure & Authorized) */}
                  <div className="flex items-center gap-2 bg-slate-50 border border-slate-100 px-3 py-1.5 rounded-xl text-xs font-mono w-full md:w-auto max-w-[180px]">
                    <Key size={12} className="text-slate-400 shrink-0" />
                    <span className="text-slate-500 font-bold tracking-widest text-[11px] flex-1">
                      {canSeePasscode ? (
                        visiblePasscodes[member.userId] ? (
                          member.passcode
                        ) : (
                          '••••'
                        )
                      ) : (
                        '•••• (Protected)'
                      )}
                    </span>
                    {canSeePasscode && (
                      <button
                        onClick={() => handleTogglePasscodeVisibility(member.userId)}
                        className="text-slate-400 hover:text-slate-700 transition-colors p-1"
                      >
                        {visiblePasscodes[member.userId] ? <EyeOff size={11} /> : <Eye size={11} />}
                      </button>
                    )}
                  </div>

                  {/* Operational Controls Actions */}
                  <div className="flex items-center gap-2 self-stretch md:self-auto justify-end">
                    
                    {/* Make/Unmake anyone Manager or Worker (Top Manager Privilege) */}
                    {canModifyRole && (
                      <button
                        onClick={() => handleToggleRole(member.userId)}
                        className={`px-3 py-1.5 rounded-lg text-[10px] font-display font-bold uppercase tracking-wider border transition-all ${
                          isTargetManager 
                            ? 'bg-rose-50 border-rose-200 text-rose-700 hover:bg-rose-100/50' 
                            : 'bg-indigo-50 border-indigo-200 text-indigo-700 hover:bg-indigo-100/50'
                        }`}
                        title="Toggle shift authority status"
                      >
                        {isTargetManager ? 'Demote to Worker' : 'Promote to Manager'}
                      </button>
                    )}

                    {/* Impersonate / Open Account directly without passcode prompt */}
                    {canImpersonate && (
                      <button
                        onClick={() => handleImpersonate(member)}
                        className="bg-indigo-600 hover:bg-indigo-700 text-white px-3 py-1.5 rounded-lg text-[10px] font-display font-bold uppercase tracking-wider transition-all flex items-center gap-1"
                        title="Instantly launch and open this staff shift view"
                      >
                        <LogIn size={11} /> Open Account
                      </button>
                    )}

                    {/* Profile Deletion (Top Manager Privilege) */}
                    {canDelete && (
                      <button
                        onClick={() => handleDeleteStaff(member.userId)}
                        className="p-1.5 text-slate-300 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-all"
                        title="Remove staff member account permanently"
                      >
                        <Trash2 size={13} />
                      </button>
                    )}
                  </div>

                </div>
              );
            })}
          </div>
        </div>

      </div>

      {/* RIGHT COLUMN: Interactive Control Forms */}
      <div className="xl:col-span-4 space-y-6">

        {/* Printer & Hardware settings card (Only Managers) */}
        {!isWorker && (
          <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm space-y-4">
            <div className="flex items-center gap-2 text-slate-900">
              <Printer size={16} className="text-slate-400" />
              <h4 className="font-display font-bold text-xs uppercase tracking-wide">POS Hardware Printer Settings</h4>
            </div>

            <p className="text-[11px] text-slate-400 leading-normal font-sans">
              Set default thermal tape dimensions, network IP addresses, or Bluetooth connections for direct hardware ticketing.
            </p>

            <div className="bg-slate-50 border border-slate-100 rounded-xl p-3.5 space-y-3.5">
              <div className="flex flex-col gap-1.5 text-[10px] text-slate-500 font-sans">
                <div className="flex justify-between border-b border-slate-200/50 pb-1">
                  <span>Paper Width:</span>
                  <span className="font-bold text-slate-700">{printerSettings.paperWidth}</span>
                </div>
                <div className="flex justify-between border-b border-slate-200/50 pb-1">
                  <span>Default Format:</span>
                  <span className="font-bold text-slate-700 capitalize">{printerSettings.defaultFormat}</span>
                </div>
                <div className="flex justify-between border-b border-slate-200/50 pb-1">
                  <span>IP/Network Address:</span>
                  <span className="font-bold text-slate-700 font-mono">{printerSettings.ipAddress || 'Not Configured'}</span>
                </div>
                <div className="flex justify-between pb-0.5">
                  <span>BT MAC Address:</span>
                  <span className="font-bold text-slate-700 font-mono">{printerSettings.bluetoothAddress || 'Not Configured'}</span>
                </div>
              </div>

              <button
                type="button"
                onClick={() => {
                  setPaperWidth(printerSettings.paperWidth);
                  setDefaultFormat(printerSettings.defaultFormat);
                  setIpAddress(printerSettings.ipAddress);
                  setBluetoothAddress(printerSettings.bluetoothAddress);
                  setShowPrinterModal(true);
                }}
                className="w-full bg-slate-900 hover:bg-slate-800 text-white font-display font-bold text-[10px] uppercase tracking-wider py-2.5 rounded-xl shadow-sm transition-all flex items-center justify-center gap-1.5"
              >
                <Sliders size={11} /> Open Printer Console
              </button>
            </div>
          </div>
        )}

        {/* My Account — self-service profile edit for every role, top manager included */}
        <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm space-y-4">
            <div className="flex items-center gap-2">
              <Key size={16} className={isTopManager ? 'text-amber-500' : 'text-emerald-500'} />
              <div>
                <h4 className="font-display font-bold text-slate-950 text-xs uppercase tracking-wide">My Account</h4>
                <p className="text-[10px] text-slate-400 mt-0.5">Change your own name, staff ID and PIN.</p>
              </div>
            </div>

            {workerPassSuccess && (
              <div className="bg-emerald-50 border border-emerald-100 rounded-xl p-3 text-xs text-emerald-700 flex items-center gap-2">
                <Check size={14} className="shrink-0" />
                <span>{workerPassSuccess}</span>
              </div>
            )}

            {workerPassError && (
              <div className="bg-rose-50 border border-rose-100 rounded-xl p-3 text-xs text-rose-700 flex items-center gap-2">
                <ShieldAlert size={14} className="shrink-0" />
                <span>{workerPassError}</span>
              </div>
            )}

            <form onSubmit={handleUpdateMyAccount} className="space-y-3.5">
              <div>
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                  My Full Name
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Jude Mukasa"
                  value={selfName}
                  onChange={(e) => setSelfName(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 text-slate-800 font-medium"
                />
              </div>

              <div>
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                  My Staff ID / Username
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. TM001"
                  value={selfId}
                  onChange={(e) => setSelfId(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono uppercase focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 text-slate-800"
                />
              </div>

              <div className="border-t border-slate-100 pt-3.5">
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                  Current PIN Code *
                </label>
                <input
                  type="password"
                  required
                  placeholder="Confirm it is you"
                  value={workerCurrentPass}
                  onChange={(e) => setWorkerCurrentPass(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 text-slate-800"
                />
              </div>

              <div>
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                  New PIN Code
                </label>
                <input
                  type="password"
                  placeholder="Leave blank to keep current PIN"
                  value={workerNewPass}
                  onChange={(e) => setWorkerNewPass(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 text-slate-800"
                />
              </div>

              <div>
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                  Confirm New PIN Code
                </label>
                <input
                  type="password"
                  placeholder="Repeat the new PIN"
                  value={workerConfirmPass}
                  onChange={(e) => setWorkerConfirmPass(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 text-slate-800"
                />
              </div>

              <button
                type="submit"
                className="w-full bg-slate-900 hover:bg-slate-800 text-white font-display font-bold text-xs uppercase tracking-wider py-2.5 rounded-xl shadow-sm transition-all"
              >
                Save My Account
              </button>
            </form>
          </div>

        {/* Register Staff Panel - Visible to managers and top managers */}
        {!isWorker && (
          <div className="bg-white border border-slate-100 rounded-2xl p-6 shadow-sm space-y-4">
            <div className="flex items-center gap-2">
              <UserPlus size={16} className="text-slate-400" />
              <div>
                <h4 className="font-display font-bold text-slate-950 text-xs uppercase tracking-wide">Register New Staff</h4>
                <p className="text-[10px] text-slate-400 mt-0.5">
                  {isTopManager ? 'Add managers and workers' : 'Register standard worker profiles'}
                </p>
              </div>
            </div>

            {formSuccess && (
              <div className="bg-green-50 border border-green-100 rounded-xl p-3 text-xs text-green-700 flex items-center gap-2">
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

            <form onSubmit={handleCreateStaff} className="space-y-3.5">
              <div>
                <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                  Full Name
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Rebecca Nakintu..."
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 font-medium"
                />
              </div>

              {isTopManager && (
                <div>
                  <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                    System Access Level
                  </label>
                  <select
                     value={newRole}
                     onChange={(e) => setNewRole(e.target.value as any)}
                     className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 font-medium"
                  >
                    <option value="worker">Worker (Checkout POS Only)</option>
                    <option value="manager">Manager (Full Dashboard)</option>
                  </select>
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                    Passcode PIN
                  </label>
                  <input
                    type="password"
                    required
                    placeholder="e.g. 5678"
                    value={newPasscode}
                    onChange={(e) => setNewPasscode(e.target.value)}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                </div>
                <div>
                  <label className="block text-[9px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1">
                    Custom ID (Optional)
                  </label>
                  <input
                    type="text"
                    placeholder="e.g. W902"
                    value={newCustomId}
                    onChange={(e) => setNewCustomId(e.target.value)}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono uppercase focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                </div>
              </div>

              <button
                type="submit"
                className="w-full bg-indigo-600 hover:bg-indigo-700 text-white font-display font-bold text-xs uppercase tracking-wider py-2.5 rounded-xl shadow-md transition-all flex items-center justify-center gap-1.5"
              >
                <UserPlus size={13} /> Save Staff Member
              </button>
            </form>
          </div>
        )}

      </div>

      {/* Printer Settings Modal */}
      <AnimatePresence>
        {showPrinterModal && (
          <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 10 }}
              className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden border border-slate-100"
            >
              {/* Modal Header */}
              <div className="bg-slate-950 px-6 py-4 text-white flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <Printer className="text-indigo-400 shrink-0" size={20} />
                  <div>
                    <h3 className="font-display font-black text-sm uppercase tracking-wide leading-tight">Printer Configuration Console</h3>
                    <p className="text-[10px] text-slate-400 font-mono">Hardware Integration Module</p>
                  </div>
                </div>
                <button
                  onClick={() => setShowPrinterModal(false)}
                  className="text-slate-400 hover:text-white transition-colors p-1"
                >
                  <X size={18} />
                </button>
              </div>

              {/* Modal Body / Form */}
              <div className="p-6 space-y-5 max-h-[70vh] overflow-y-auto">
                {modalSuccess && (
                  <div className="bg-green-50 border border-green-100 rounded-xl p-3 text-xs text-green-700 flex items-center gap-2">
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

                {/* Form fields */}
                <div className="space-y-4">
                  {/* Paper Width Selector */}
                  <div>
                    <label className="block text-[10px] font-display font-bold text-slate-400 uppercase tracking-wider mb-2">
                      Thermal Paper Dimensions
                    </label>
                    <div className="grid grid-cols-2 gap-3">
                      <button
                        type="button"
                        onClick={() => setPaperWidth('58mm')}
                        className={`py-2 px-3 rounded-xl border font-display font-bold text-xs transition-all flex items-center justify-center gap-1.5 ${
                          paperWidth === '58mm'
                            ? 'bg-slate-900 text-white border-slate-900 shadow-sm'
                            : 'bg-slate-50 text-slate-600 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        58mm Paper Width
                      </button>
                      <button
                        type="button"
                        onClick={() => setPaperWidth('80mm')}
                        className={`py-2 px-3 rounded-xl border font-display font-bold text-xs transition-all flex items-center justify-center gap-1.5 ${
                          paperWidth === '80mm'
                            ? 'bg-slate-900 text-white border-slate-900 shadow-sm'
                            : 'bg-slate-50 text-slate-600 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        80mm Paper Width
                      </button>
                    </div>
                    <p className="text-[9px] text-slate-400 mt-1.5 leading-normal">
                      Select 58mm for handheld/portable thermal slips, or 80mm for standard high-speed countertop register roll formats.
                    </p>
                  </div>

                  {/* Print Format Toggle */}
                  <div>
                    <label className="block text-[10px] font-display font-bold text-slate-400 uppercase tracking-wider mb-2">
                      Default Communication Format
                    </label>
                    <div className="grid grid-cols-2 gap-3">
                      <button
                        type="button"
                        onClick={() => setDefaultFormat('receipt')}
                        className={`py-2 px-3 rounded-xl border font-display font-bold text-xs transition-all flex items-center justify-center gap-1.5 ${
                          defaultFormat === 'receipt'
                            ? 'bg-slate-900 text-white border-slate-900 shadow-sm'
                            : 'bg-slate-50 text-slate-600 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        Receipt Slip (POS)
                      </button>
                      <button
                        type="button"
                        onClick={() => setDefaultFormat('sticker')}
                        className={`py-2 px-3 rounded-xl border font-display font-bold text-xs transition-all flex items-center justify-center gap-1.5 ${
                          defaultFormat === 'sticker'
                            ? 'bg-slate-900 text-white border-slate-900 shadow-sm'
                            : 'bg-slate-50 text-slate-600 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        Barcode Sticker
                      </button>
                    </div>
                    <p className="text-[9px] text-slate-400 mt-1.5 leading-normal">
                      Determines default rendering logic for cash registers or barcodes in storage.
                    </p>
                  </div>

                  {/* Network IP Connection */}
                  <div className="border-t border-slate-100 pt-3">
                    <label className="block text-[10px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                      <Wifi size={12} className="text-slate-400" />
                      Printer IP Address (Network TCP)
                    </label>
                    <input
                      type="text"
                      placeholder="e.g. 192.168.1.100"
                      value={ipAddress}
                      onChange={(e) => setIpAddress(e.target.value)}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                    <p className="text-[9px] text-slate-400 mt-1 leading-normal">
                      Used for ethernet thermal printers. Port 9100 stream will be transmitted.
                    </p>
                  </div>

                  {/* Bluetooth Connection Address */}
                  <div>
                    <label className="block text-[10px] font-display font-bold text-slate-400 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                      <Bluetooth size={12} className="text-slate-400" />
                      Bluetooth Hardware MAC/UUID
                    </label>
                    <input
                      type="text"
                      placeholder="e.g. 00:11:22:33:FF:EE"
                      value={bluetoothAddress}
                      onChange={(e) => setBluetoothAddress(e.target.value)}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                    <p className="text-[9px] text-slate-400 mt-1 leading-normal">
                      For pairing bluetooth hardware. Web Bluetooth interfaces with RFCOMM channels.
                    </p>
                  </div>
                </div>

                {/* Print Test Action */}
                <div className="bg-indigo-50/50 border border-indigo-100/50 rounded-xl p-3.5 space-y-2">
                  <h5 className="font-display font-bold text-[10px] uppercase text-indigo-950 flex items-center gap-1">
                    🎯 Hardware Verification Testing
                  </h5>
                  <p className="text-[9px] text-indigo-900/70 leading-normal">
                    Click below to transmit a clean, multi-layered verification receipt byte stream directly to the configured printer interface.
                  </p>
                  <button
                    type="button"
                    onClick={handleTestPrint}
                    className="bg-indigo-600 hover:bg-indigo-700 text-white font-display font-bold text-[10px] uppercase tracking-wider py-1.5 px-3 rounded-lg shadow-sm transition-all flex items-center gap-1"
                  >
                    <Printer size={11} /> Send Hardware Test Print
                  </button>
                </div>
              </div>

              {/* Modal Footer */}
              <div className="p-4 bg-slate-50 border-t border-slate-100 flex gap-2">
                <button
                  type="button"
                  onClick={() => setShowPrinterModal(false)}
                  className="flex-1 bg-white hover:bg-slate-100 border border-slate-200 text-slate-700 rounded-xl py-2 font-display font-bold text-[10px] uppercase tracking-wider transition-all"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={handleSavePrinterSettings}
                  className="flex-1 bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2 font-display font-bold text-[10px] uppercase tracking-wider transition-all shadow-md"
                >
                  Save & Apply Config
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

    </div>
  );
};

export default StaffSettingsView;
