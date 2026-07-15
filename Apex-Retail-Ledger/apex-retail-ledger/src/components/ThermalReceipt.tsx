import React, { useState } from 'react';
import { Sale } from '../types';
import { Printer, Download, CheckCircle2, AlertCircle } from 'lucide-react';
import { localDB } from '../utils/localDB';

interface ThermalReceiptProps {
  sale: Sale;
  onClose: () => void;
}

export const ThermalReceipt: React.FC<ThermalReceiptProps> = ({ sale, onClose }) => {
  const [printStatus, setPrintStatus] = useState<{ type: 'info' | 'success' | 'error'; message: string } | null>(null);

  // Read current printer width settings
  const settings = localDB.getPrinterSettings();
  const is80mm = settings.paperWidth === '80mm';

  const handlePrint = () => {
    try {
      window.print();
      setPrintStatus({
        type: 'success',
        message: 'Standard print dialog requested. If it did not appear, click "Export & Print File" or open in a new tab.'
      });
    } catch (err: any) {
      console.warn("Print dialog blocked by sandboxed iframe:", err);
      setPrintStatus({
        type: 'error',
        message: 'Browser print restricted inside sandbox. Please click "Export & Print File" or open in a new tab.'
      });
    }
  };

  const exportAndPrintHTML = () => {
    const htmlContent = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Receipt_${sale.id}</title>
  <style>
    body {
      margin: 0;
      padding: 10px;
      font-family: monospace;
      background: white;
      color: black;
      width: ${is80mm ? '80mm' : '58mm'};
    }
    .receipt {
      width: 100%;
    }
    .text-center { text-align: center; }
    .text-right { text-align: right; }
    .flex { display: flex; justify-content: space-between; }
    .bold { font-weight: bold; }
    .border-dashed { border-top: 1px dashed #000; margin: 8px 0; }
    .item-row { display: flex; justify-content: space-between; font-size: 11px; }
  </style>
</head>
<body onload="window.print()">
  <div class="receipt">
    <div class="text-center">
      <h2 style="margin: 0 0 4px 0; font-size: 14px;">APEX SUPERMARKET</h2>
      <p style="margin: 0; font-size: 10px;">Plot 12, Kampala Plaza Rd</p>
      <p style="margin: 0; font-size: 10px;">Tel: +256 702 345 678</p>
    </div>
    <div class="border-dashed"></div>
    <p style="margin: 2px 0; font-size: 10px;"><b>SALE ID:</b> ${sale.id}</p>
    <p style="margin: 2px 0; font-size: 10px;"><b>Date:</b> ${new Date(sale.timestamp).toLocaleString()}</p>
    <p style="margin: 2px 0; font-size: 10px;"><b>Cashier:</b> ${sale.cashierName} (${sale.cashierId})</p>
    <div class="border-dashed"></div>
    <div class="flex bold" style="font-size: 10px;">
      <span>ITEM</span>
      <span style="width: ${is80mm ? '80px' : '50px'}; text-align: right;">QTY</span>
      <span style="width: ${is80mm ? '120px' : '80px'}; text-align: right;">TOTAL</span>
    </div>
    <div class="border-dashed"></div>
    ${sale.items.map(item => `
      <div style="margin-bottom: 6px;">
        <div class="flex" style="font-size: 11px;">
          <span style="font-weight: bold;">${item.productName}</span>
          <span style="width: ${is80mm ? '80px' : '50px'}; text-align: right;">x${item.quantity}</span>
          <span style="width: ${is80mm ? '120px' : '80px'}; text-align: right;">${item.totalSellingPrice.toLocaleString()}</span>
        </div>
        <div style="font-size: 9px; color: #555; padding-left: 4px;">@ ${item.sellingPrice.toLocaleString()} / unit</div>
      </div>
    `).join('')}
    <div class="border-dashed"></div>
    <div class="flex" style="font-size: 11px;"><span>SUBTOTAL:</span> <span>shs ${sale.totalAmount.toLocaleString()}</span></div>
    <div class="flex bold" style="font-size: 12px; margin-top: 4px;"><span>TOTAL:</span> <span>shs ${sale.totalAmount.toLocaleString()}</span></div>
    <div class="border-dashed" style="border-top-style: dotted;"></div>
    <div class="flex" style="font-size: 10px;"><span>PAY METHOD:</span> <span style="text-transform: uppercase;">${sale.paymentMethod.replace('_', ' ')}</span></div>
    ${sale.paymentMethod === 'mobile_money' && sale.mobileMoneyTxId ? `<div class="flex bold" style="font-size: 10px; color: #000;"><span>REF TXID:</span> <span>${sale.mobileMoneyTxId}</span></div>` : ''}
    <div class="flex" style="font-size: 10px;"><span>AMOUNT PAID:</span> <span>shs ${sale.amountPaid.toLocaleString()}</span></div>
    <div class="flex bold" style="font-size: 10px; color: #000;"><span>CHANGE DUE:</span> <span>shs ${sale.changeDue.toLocaleString()}</span></div>
    <div class="border-dashed"></div>
    <div class="text-center" style="font-size: 10px; margin-top: 15px;">
      <p style="margin: 0;">THANK YOU FOR SHOPPING WITH US</p>
      <p style="margin: 4px 0 0 0; font-weight: bold;">APEX CLOUD LEDGER SYSTEM</p>
    </div>
  </div>
</body>
</html>`;

    const blob = new Blob([htmlContent], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `receipt_${sale.id}.html`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    setPrintStatus({
      type: 'success',
      message: '✅ File downloaded! Double click the receipt file to print instantly.'
    });
  };

  return (
    <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
      <div className={`bg-white rounded-2xl shadow-2xl ${is80mm ? 'max-w-md' : 'max-w-sm'} w-full overflow-hidden border border-slate-100 flex flex-col md:max-h-[95vh]`}>
        {/* Header Options */}
        <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="flex h-2.5 w-2.5 rounded-full bg-emerald-500 animate-ping"></span>
            <span className="font-display font-semibold text-slate-800 text-sm">Receipt Issued ({settings.paperWidth})</span>
          </div>
          <div className="flex gap-2">
            <button
              onClick={exportAndPrintHTML}
              className="p-1.5 hover:bg-slate-200 rounded-lg text-slate-600 transition-colors"
              title="Download Printable File"
            >
              <Download size={16} />
            </button>
            <button
              onClick={handlePrint}
              className="p-1.5 hover:bg-slate-200 rounded-lg text-slate-600 transition-colors"
              title="Print Receipt"
            >
              <Printer size={16} />
            </button>
          </div>
        </div>

        {/* Dynamic print status/warning HUD */}
        {printStatus && (
          <div className={`px-5 py-2.5 text-[11px] font-sans border-b flex items-start gap-2 ${
            printStatus.type === 'success'
              ? 'bg-emerald-50 border-emerald-100 text-emerald-800'
              : printStatus.type === 'error'
              ? 'bg-rose-50 border-rose-100 text-rose-800'
              : 'bg-indigo-50 border-indigo-100 text-indigo-800'
          }`}>
            <CheckCircle2 size={14} className="mt-0.5 shrink-0" />
            <div>{printStatus.message}</div>
          </div>
        )}

        {/* Paper Receipt Container (Simulated Thermal Roll) */}
        <div className="flex-1 overflow-y-auto p-6 bg-slate-100 flex justify-center">
          <div 
            id="thermal-print-area"
            className={`${is80mm ? 'w-[340px]' : 'w-[280px]'} bg-white px-5 py-6 shadow-md border-t-4 border-amber-500 rounded-sm font-mono text-xs text-slate-800 relative select-text`}
            style={{ 
              backgroundImage: 'radial-gradient(ellipse at bottom, #f1f5f9 2px, transparent 3px)',
              backgroundSize: '8px 12px',
              backgroundPosition: 'bottom'
            }}
          >
            {/* Supermarket Header */}
            <div className="text-center mb-4">
              <h2 className="font-extrabold text-sm tracking-wider text-slate-950 uppercase">APEX SUPERMARKET</h2>
              <p className="text-[10px] text-slate-500">Plot 12, Kampala Plaza Rd</p>
              <p className="text-[10px] text-slate-500">Tel: +256 702 345 678</p>
              <div className="border-t border-dashed border-slate-300 my-2"></div>
              <p className="text-left font-bold text-[10px] text-slate-600">SALE ID: {sale.id}</p>
              <p className="text-left text-[10px] text-slate-500">Date: {new Date(sale.timestamp).toLocaleString()}</p>
              <p className="text-left text-[10px] text-slate-500">Cashier: {sale.cashierName} ({sale.cashierId})</p>
            </div>

            <div className="border-t border-dashed border-slate-300 my-2"></div>

            {/* Header Columns */}
            <div className="flex justify-between font-bold text-slate-950 text-[10px] mb-1">
              <span className={is80mm ? 'w-3/5' : 'w-1/2'}>ITEM</span>
              <span className={is80mm ? 'w-1/12 text-right' : 'w-1/6 text-right'}>QTY</span>
              <span className={is80mm ? 'w-3/10 text-right' : 'w-1/3 text-right'}>TOTAL</span>
            </div>
            
            <div className="border-t border-dashed border-slate-200 mb-2"></div>

            {/* Items */}
            <div className="space-y-2 mb-4">
              {sale.items.map((item) => (
                <div key={item.id} className="text-[10px] leading-tight">
                  <div className="flex justify-between font-medium text-slate-950">
                    <span className={`${is80mm ? 'w-3/5' : 'w-1/2'} truncate`}>{item.productName}</span>
                    <span className={is80mm ? 'w-1/12 text-right' : 'w-1/6 text-right'}>x{item.quantity}</span>
                    <span className={is80mm ? 'w-3/10 text-right' : 'w-1/3 text-right'}>{(item.totalSellingPrice).toLocaleString()}</span>
                  </div>
                  <div className="text-[9px] text-slate-400 pl-1">
                    @ {item.sellingPrice.toLocaleString()} / unit
                  </div>
                </div>
              ))}
            </div>

            <div className="border-t border-dashed border-slate-300 my-2"></div>

            {/* Calculations */}
            <div className="space-y-1 text-xs">
              <div className="flex justify-between">
                <span>SUBTOTAL:</span>
                <span>shs {sale.totalAmount.toLocaleString()}</span>
              </div>
              <div className="flex justify-between font-bold text-slate-950">
                <span>TOTAL:</span>
                <span>shs {sale.totalAmount.toLocaleString()}</span>
              </div>
              <div className="border-t border-dashed border-slate-200 my-1"></div>
              <div className="flex justify-between text-[10px] text-slate-500">
                <span>PAY METHOD:</span>
                <span className="uppercase">{sale.paymentMethod.replace('_', ' ')}</span>
              </div>
              {sale.paymentMethod === 'mobile_money' && sale.mobileMoneyTxId && (
                <div className="flex justify-between text-[10px] text-indigo-700 font-bold">
                  <span>REF TXID:</span>
                  <span className="uppercase">{sale.mobileMoneyTxId}</span>
                </div>
              )}
              <div className="flex justify-between text-[10px] text-slate-500">
                <span>AMOUNT PAID:</span>
                <span>shs {sale.amountPaid.toLocaleString()}</span>
              </div>
              <div className="flex justify-between font-bold text-emerald-700 text-[10px]">
                <span>CHANGE DUE:</span>
                <span>shs {sale.changeDue.toLocaleString()}</span>
              </div>
            </div>

            <div className="border-t border-dashed border-slate-300 my-4"></div>

            {/* Barcode representation */}
            <div className="flex flex-col items-center justify-center mb-2">
              <div className={`h-7 ${is80mm ? 'w-56' : 'w-44'} bg-slate-900 flex items-center justify-around px-2 opacity-80`}>
                {Array.from({ length: is80mm ? 40 : 32 }).map((_, i) => (
                  <div 
                    key={i} 
                    className="bg-white h-full" 
                    style={{ 
                      width: `${(i % 3 === 0 ? 3 : i % 2 === 0 ? 1 : 2)}px`,
                      opacity: i % 7 === 0 ? 0 : 1
                    }}
                  />
                ))}
              </div>
              <p className="text-[9px] text-slate-400 tracking-[0.25em] mt-1">{sale.id}</p>
            </div>

            {/* Footer */}
            <div className="text-center text-[9px] text-slate-400 mt-4 leading-normal">
              <p>THANK YOU FOR SHOPPING WITH US</p>
              <p className="font-bold text-slate-600 text-[10px] mt-1">APEX CLOUD LEDGER SYSTEM</p>
              <p>Backed Up & Synced Securely</p>
            </div>
          </div>
        </div>

        {/* Footer Actions */}
        <div className="p-4 bg-slate-50 border-t border-slate-100 flex flex-col gap-2">
          <div className="flex gap-2">
            <button
              onClick={handlePrint}
              className="flex-1 bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2.5 font-display font-medium text-xs uppercase tracking-wide transition-all shadow-sm hover:shadow flex items-center justify-center gap-2"
            >
              <Printer size={15} />
              Print Dialog
            </button>
            <button
              onClick={exportAndPrintHTML}
              className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl py-2.5 font-display font-medium text-xs uppercase tracking-wide transition-all shadow-sm hover:shadow flex items-center justify-center gap-2"
            >
              <Download size={15} />
              Export & Print
            </button>
          </div>
          <button
            onClick={onClose}
            className="w-full bg-white hover:bg-slate-100 border border-slate-200 text-slate-700 rounded-xl py-2 font-display font-medium text-xs uppercase tracking-wide transition-all"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};
export default ThermalReceipt;
