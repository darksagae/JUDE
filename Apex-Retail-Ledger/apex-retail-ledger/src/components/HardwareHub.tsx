import React, { useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { Cpu, Printer, Scan, CheckCircle2, AlertCircle, RefreshCw, Smartphone, HelpCircle, Power, Zap } from 'lucide-react';
import { hardwareManager, PairedPrinter } from '../utils/hardware';

interface HardwareHubProps {
  onPrinterChanged?: () => void;
}

export const HardwareHub: React.FC<HardwareHubProps> = ({ onPrinterChanged }) => {
  const [paired, setPaired] = useState<PairedPrinter | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [recentPrintLog, setRecentPrintLog] = useState<string[]>([]);
  const [reconnected, setReconnected] = useState<boolean>(false);

  useEffect(() => {
    setPaired(hardwareManager.getPairedPrinter());
    
    // Attempt background silent reconnect to USB printer if previously configured
    hardwareManager.reconnectPrinter().then(success => {
      if (success) {
        setReconnected(true);
      }
    });

    // Custom logger hook to capture ESC/POS print jobs in UI
    const originalPrint = hardwareManager.printRawESCPOS;
    hardwareManager.printRawESCPOS = async (data: Uint8Array) => {
      const timestamp = new Date().toLocaleTimeString();
      const bytesStr = Array.from(data.slice(0, 32))
        .map(b => b.toString(16).toUpperCase().padStart(2, '0'))
        .join(' ');
      const logEntry = `[${timestamp}] Transmitted ${data.length} bytes -> ESC/POS Prefix: [${bytesStr}...]`;
      
      setRecentPrintLog(prev => [logEntry, ...prev.slice(0, 9)]);
      return originalPrint(data);
    };

    return () => {
      hardwareManager.printRawESCPOS = originalPrint;
    };
  }, []);

  const handlePairUSB = async () => {
    setLoading(true);
    setError(null);
    try {
      const config = await hardwareManager.pairUSBPrinter();
      setPaired(config);
      setReconnected(true);
      if (onPrinterChanged) onPrinterChanged();
    } catch (err: any) {
      setError(err.message || "Failed to establish WebUSB handshake.");
    } finally {
      setLoading(false);
    }
  };

  const handlePairSerial = async () => {
    setLoading(true);
    setError(null);
    try {
      const config = await hardwareManager.pairSerialPrinter();
      setPaired(config);
      setReconnected(true);
      if (onPrinterChanged) onPrinterChanged();
    } catch (err: any) {
      setError(err.message || "Failed to establish WebSerial handshake.");
    } finally {
      setLoading(false);
    }
  };

  const handleDisconnect = () => {
    hardwareManager.setPairedPrinter(null);
    setPaired(null);
    setReconnected(false);
    setError(null);
    if (onPrinterChanged) onPrinterChanged();
  };

  return (
    <div className="bg-white border border-slate-100 rounded-2xl shadow-sm p-5 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-slate-50 pb-3">
        <div className="flex items-center gap-2">
          <div className="p-1.5 bg-emerald-50 text-emerald-600 rounded-lg">
            <Cpu size={16} className="animate-pulse" />
          </div>
          <div>
            <h3 className="font-display font-bold text-xs text-slate-800 uppercase tracking-wider">
              High-Speed Hardware Engine
            </h3>
            <p className="text-[10px] text-slate-400">Direct client-side USB/Serial printer and scanner telemetry</p>
          </div>
        </div>
        <span className="bg-indigo-50 text-indigo-700 text-[9px] font-mono font-bold px-2 py-0.5 rounded uppercase">
          V1.0.4-WEB
        </span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Left Side: Connection Status and Action Buttons */}
        <div className="space-y-3">
          {paired ? (
            <div className="bg-emerald-50/60 border border-emerald-100 rounded-xl p-3.5 space-y-2.5">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-emerald-800">
                  <CheckCircle2 size={16} className="text-emerald-600" />
                  <span className="font-display font-bold text-xs">{paired.name}</span>
                </div>
                <button
                  onClick={handleDisconnect}
                  className="text-[10px] font-display font-semibold text-red-500 hover:text-red-700 transition-colors uppercase"
                >
                  Disconnect
                </button>
              </div>
              <div className="flex items-center gap-4 text-[10px] text-slate-500 font-sans">
                <div className="flex items-center gap-1">
                  <span className="h-1.5 w-1.5 bg-emerald-500 rounded-full"></span>
                  Protocol: <span className="font-bold text-slate-700 uppercase">{paired.type} RAW</span>
                </div>
                <div className="flex items-center gap-1">
                  <span className="h-1.5 w-1.5 bg-emerald-500 rounded-full"></span>
                  Status: <span className="font-bold text-emerald-700">{reconnected ? 'Connected' : 'Offline / Standby'}</span>
                </div>
              </div>
            </div>
          ) : (
            <div className="bg-slate-50 border border-slate-200/40 rounded-xl p-3.5 text-center">
              <Printer size={20} className="mx-auto text-slate-400 mb-1.5" />
              <p className="font-display font-semibold text-slate-700 text-xs">No Direct Printer Paired</p>
              <p className="text-[10px] text-slate-400 mt-0.5">
                Standard window.print dialog fallback active. Pair a thermal printer for instant checkout printing.
              </p>
            </div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-100 text-red-700 p-2.5 rounded-xl flex items-start gap-2 text-[10px]">
              <AlertCircle size={14} className="mt-0.5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* Action Row */}
          {!paired && (
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={handlePairUSB}
                disabled={loading}
                className="bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2 font-display font-bold text-[11px] transition-all flex items-center justify-center gap-1.5 shadow-sm"
              >
                <Printer size={13} />
                {loading ? 'Handshake...' : 'Pair USB Printer'}
              </button>
              <button
                onClick={handlePairSerial}
                disabled={loading}
                className="bg-white hover:bg-slate-50 border border-slate-200 text-slate-700 rounded-xl py-2 font-display font-bold text-[11px] transition-all flex items-center justify-center gap-1.5"
              >
                <Cpu size={13} className="text-indigo-600" />
                Pair COM Port
              </button>
            </div>
          )}
        </div>

        {/* Right Side: Telemetry / Real-time Terminal Log */}
        <div className="flex flex-col bg-slate-950 rounded-xl border border-slate-900 p-3 h-32 overflow-hidden relative">
          <div className="flex items-center justify-between text-[9px] font-mono text-slate-500 border-b border-slate-900 pb-1 mb-1 bg-slate-950 shrink-0">
            <span>HARDWARE STACK STREAM LOGS</span>
            <div className="flex items-center gap-1">
              <span className="h-1 w-1 bg-emerald-500 rounded-full animate-ping"></span>
              <span className="text-emerald-500 uppercase font-black text-[8px]">ONLINE</span>
            </div>
          </div>
          <div className="flex-1 overflow-y-auto space-y-1 font-mono text-[9px] text-slate-300 leading-normal select-text pr-1 custom-scrollbar">
            {recentPrintLog.length === 0 ? (
              <p className="text-slate-600 italic">No hardware signals detected yet. Perform checkout or print barcode stickers to observe binary outputs...</p>
            ) : (
              recentPrintLog.map((log, idx) => (
                <div key={idx} className="hover:bg-slate-900/60 px-1 py-0.5 rounded leading-tight">
                  {log}
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Helpful Info footer */}
      <div className="bg-slate-50 rounded-xl p-2.5 flex items-start gap-2.5 border border-slate-100">
        <Zap size={14} className="text-indigo-500 shrink-0 mt-0.5" />
        <p className="text-[10px] text-slate-500 leading-normal font-sans">
          <strong>Cashier Tip:</strong> Pairing a USB/COM receipt printer connects your web browser directly to the printer's hardware buffer. Receipts will instantly spit out and auto-cut without invoking the slow print prompt. Perfect for bulk lanes!
        </p>
      </div>
    </div>
  );
};
export default HardwareHub;
