import React, { useState, useMemo } from 'react';
import { Product, SaleItem, productSalePrice } from '../types';
import localDB, { generateId } from '../utils/localDB';
import { Search, ShoppingCart, Trash2, Plus, Minus, CreditCard, AlertTriangle, CalendarRange, Sparkles, Sliders } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ThermalReceipt from './ThermalReceipt';
import HardwareHub from './HardwareHub';
import { hardwareManager } from '../utils/hardware';

const isProductExpired = (p: Product) => {
  if (!p.expirationDate) return false;
  const exp = new Date(p.expirationDate);
  const today = new Date('2026-07-03'); // Adjusted to current 2026-07-03 time context
  return exp <= today;
};

const isProductNearExpiry = (p: Product) => {
  if (!p.expirationDate) return false;
  const exp = new Date(p.expirationDate);
  const today = new Date('2026-07-03');
  const diffDays = Math.ceil((exp.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
  return diffDays >= 0 && diffDays <= 7;
};

interface POSViewProps {
  onSaleComplete: () => void;
}

export const POSView: React.FC<POSViewProps> = ({ onSaleComplete }) => {
  const [products, setProducts] = useState<Product[]>(() => localDB.getProducts());
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [cart, setCart] = useState<{ product: Product; quantity: number }[]>([]);
  const [paymentMethod, setPaymentMethod] = useState<'cash' | 'mobile_money' | 'card' | 'partial'>('cash');
  const [amountPaid, setAmountPaid] = useState<number | ''>('');
  const [mobileMoneyTxId, setMobileMoneyTxId] = useState('');
  // Partial / loan sale fields (customer takes goods now, pays the balance later)
  const [customerName, setCustomerName] = useState('');
  const [customerContact, setCustomerContact] = useState('');
  const [pledgeDate, setPledgeDate] = useState(
    () => new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10)
  );
  const [completedSale, setCompletedSale] = useState<any | null>(null);
  const [showNotificationDetails, setShowNotificationDetails] = useState(false);
  const [showHardwareConfig, setShowHardwareConfig] = useState(false);
  const [toast, setToast] = useState<{ type: 'success' | 'error' | 'warning'; message: string } | null>(null);

  const toastTimeoutRef = React.useRef<any>(null);

  const showToast = (message: string, type: 'success' | 'error' | 'warning' = 'success') => {
    if (toastTimeoutRef.current) {
      clearTimeout(toastTimeoutRef.current);
    }
    setToast({ type, message });
    toastTimeoutRef.current = setTimeout(() => {
      setToast(null);
    }, 2000);
  };

  const lowStockItems = useMemo(() => products.filter(p => p.currentStock <= p.minStockLevel), [products]);
  const expiredItems = useMemo(() => products.filter(p => isProductExpired(p)), [products]);
  const nearExpiryItems = useMemo(() => products.filter(p => isProductNearExpiry(p)), [products]);

  // Sync products on view load
  const handleRefreshProducts = () => {
    setProducts(localDB.getProducts());
  };

  // Hardware Barcode Scanner Listener (Keyboard Wedge Emulation)
  React.useEffect(() => {
    let buffer = '';
    let lastKeyTime = Date.now();

    const handleKeyDown = (e: KeyboardEvent) => {
      // Ignore modifier keys
      if (e.key === 'Shift' || e.key === 'Control' || e.key === 'Alt' || e.key === 'Meta') {
        return;
      }

      const currentTime = Date.now();
      const timeDiff = currentTime - lastKeyTime;
      lastKeyTime = currentTime;

      // Enter key indicates scanner finished typed SKU
      if (e.key === 'Enter') {
        if (buffer.length >= 3) {
          const scannedSku = buffer.trim().toUpperCase();
          const foundProduct = products.find(p => p.sku.toUpperCase() === scannedSku);
          
          if (foundProduct) {
            addToCart(foundProduct);
            // Play a hardware beep feedback using Web Audio API
            try {
              const audioCtx = new (window.AudioContext || (window as any).webkitAudioContext)();
              const oscillator = audioCtx.createOscillator();
              const gainNode = audioCtx.createGain();
              oscillator.connect(gainNode);
              gainNode.connect(audioCtx.destination);
              oscillator.type = 'sine';
              oscillator.frequency.setValueAtTime(1000, audioCtx.currentTime);
              gainNode.gain.setValueAtTime(0.08, audioCtx.currentTime);
              oscillator.start();
              oscillator.stop(audioCtx.currentTime + 0.1);
            } catch (err) {}

            setSearchQuery('');
            showToast(`✅ Scan Success: Added "${foundProduct.name}" to cart!`, 'success');
          } else {
            showToast(`❌ Scanned SKU "${scannedSku}" not found in catalog.`, 'error');
          }
          buffer = '';
        }
        return;
      }

      // Buffer characters if they are entered extremely rapidly (standard keyboard wedge emulation)
      // or if no text field is currently focused
      const isInputFocused = document.activeElement instanceof HTMLInputElement || 
                             document.activeElement instanceof HTMLTextAreaElement;

      if (!isInputFocused || timeDiff < 45) {
        if (e.key.length === 1) {
          if (timeDiff > 250) {
            buffer = ''; // timeout reset
          }
          buffer += e.key;
        }
      } else {
        buffer = '';
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [products]);

  const categories = useMemo(() => {
    const cats = new Set(products.map(p => p.category));
    return ['All', ...Array.from(cats)];
  }, [products]);

  const filteredProducts = useMemo(() => {
    return products.filter(p => {
      const matchesSearch = p.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
                            p.sku.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesCategory = selectedCategory === 'All' || p.category === selectedCategory;
      return matchesSearch && matchesCategory;
    });
  }, [products, searchQuery, selectedCategory]);


  const addToCart = (product: Product) => {
    if (product.currentStock <= 0) return;

    // Expired commodities are sold freely (no supervisor passcode / warning) —
    // moving expired stock out at any price beats a total write-off.
    setCart(prev => {
      const existing = prev.find(item => item.product.id === product.id);
      if (existing) {
        if (existing.quantity >= product.currentStock) return prev; // Limit to stock
        return prev.map(item => 
          item.product.id === product.id 
            ? { ...item, quantity: item.quantity + 1 } 
            : item
        );
      }
      return [...prev, { product, quantity: 1 }];
    });
  };

  const removeFromCart = (productId: string) => {
    setCart(prev => prev.filter(item => item.product.id !== productId));
  };

  const updateQuantity = (productId: string, delta: number) => {
    setCart(prev => {
      return prev.map(item => {
        if (item.product.id === productId) {
          const newQty = item.quantity + delta;
          if (newQty <= 0) return null;
          if (newQty > item.product.currentStock) return item; // limit to stock
          return { ...item, quantity: newQty };
        }
        return item;
      }).filter(Boolean) as { product: Product; quantity: number }[];
    });
  };

  const cartTotal = useMemo(() => {
    return cart.reduce((acc, item) => acc + productSalePrice(item.product) * item.quantity, 0);
  }, [cart]);

  const cartBuyingTotal = useMemo(() => {
    return cart.reduce((acc, item) => acc + item.product.buyingPrice * item.quantity, 0);
  }, [cart]);

  const changeDue = useMemo(() => {
    if (paymentMethod === 'partial') return 0; // change is never given on a credit sale
    if (amountPaid === '') return 0;
    return Math.max(0, amountPaid - cartTotal);
  }, [amountPaid, cartTotal, paymentMethod]);

  // On a partial sale, whatever isn't paid in cash becomes a loan balance.
  const loanAmount = useMemo(() => {
    if (paymentMethod !== 'partial') return 0;
    const cash = amountPaid === '' ? 0 : Number(amountPaid);
    return Math.max(0, cartTotal - cash);
  }, [paymentMethod, amountPaid, cartTotal]);

  const handleCheckout = (e: React.FormEvent) => {
    e.preventDefault();
    if (cart.length === 0) return;
    
    if (paymentMethod === 'mobile_money' && !mobileMoneyTxId.trim()) {
      showToast("⚠️ Mobile Money Transaction ID is required", "warning");
      return;
    }

    // Floor guard: never sell any non-expired line below its limit price. The
    // sale price is fixed to each product's sale price, so this only triggers on
    // a product mis-saved with a sale price under its limit.
    for (const item of cart) {
      const p = item.product;
      const limit = (p.wholesalePrice ?? p.retailPrice ?? p.sellingPrice) || 0;
      if (!isProductExpired(p) && limit > 0 && productSalePrice(p) < limit) {
        showToast(`⚠️ ${p.name}: price is below its limit — cannot sell. Fix its pricing in Inventory.`, "error");
        return;
      }
    }

    let cashVal: number;
    if (paymentMethod === 'partial') {
      cashVal = amountPaid === '' ? 0 : Number(amountPaid);
      if (cashVal >= cartTotal) {
        showToast("⚠️ Cash covers the full total — use Cash, not Partial.", "warning");
        return;
      }
      if (!customerName.trim()) {
        showToast("⚠️ Customer name is required for the loan balance", "warning");
        return;
      }
      if (customerContact.trim().length !== 10) {
        showToast("⚠️ Contact must be exactly 10 digits for a loan sale", "warning");
        return;
      }
    } else {
      cashVal = paymentMethod === 'cash'
        ? (amountPaid === '' ? cartTotal : amountPaid)
        : cartTotal;
      if (cashVal < cartTotal) {
        showToast("⚠️ Insufficient payment amount", "warning");
        return;
      }
    }

    const session = localDB.getSession();

    const saleItems: SaleItem[] = cart.map(item => {
      const price = productSalePrice(item.product);
      return {
        id: generateId(),
        productId: item.product.id,
        productName: item.product.name,
        quantity: item.quantity,
        buyingPrice: item.product.buyingPrice,
        sellingPrice: price,
        totalBuyingPrice: item.product.buyingPrice * item.quantity,
        totalSellingPrice: price * item.quantity,
        profit: (price - item.product.buyingPrice) * item.quantity
      };
    });

    // Cash actually collected now (the loan portion is not cash in the drawer).
    const settled = paymentMethod === 'partial'
      ? cashVal
      : (cashVal > cartTotal ? cartTotal : cashVal);
    const resolvedPledge = paymentMethod === 'partial' ? pledgeDate : undefined;

    const sale = localDB.addSale({
      items: saleItems,
      totalAmount: cartTotal,
      totalBuyingPrice: cartBuyingTotal,
      totalProfit: cartTotal - cartBuyingTotal,
      paymentMethod,
      amountPaid: settled,
      changeDue: paymentMethod === 'partial' ? 0 : (Number(cashVal) - cartTotal),
      loanAmount: paymentMethod === 'partial' ? loanAmount : 0,
      customerName: paymentMethod === 'partial' ? customerName.trim() : undefined,
      customerContact: paymentMethod === 'partial' ? customerContact.trim() : undefined,
      loanPledgeDate: resolvedPledge,
      cashierId: session.userId,
      cashierName: session.name,
      mobileMoneyTxId: paymentMethod === 'mobile_money' ? mobileMoneyTxId.trim().toUpperCase() : undefined
    });

    // Register the unpaid balance as a loan, carrying the sale's profit margin so
    // the credit portion's profit is recognised (cash-basis) as it is repaid.
    if (paymentMethod === 'partial' && loanAmount > 0) {
      localDB.addLoan({
        customerName: customerName.trim(),
        customerContact: customerContact.trim(),
        amount: loanAmount,
        pledgeDate,
        saleId: sale.id,
        notes: `Balance from POS sale ${sale.id}`,
        profitRate: cartTotal > 0 ? (cartTotal - cartBuyingTotal) / cartTotal : 0
      });
    }

    // Check if direct hardware thermal printer is paired
    const pairedPrinter = hardwareManager.getPairedPrinter();
    if (pairedPrinter) {
      const bytes = hardwareManager.generateReceiptBytes(sale);
      hardwareManager.printRawESCPOS(bytes).catch(err => {
        console.error("Hardware direct print failed:", err);
      });
    }

    setCompletedSale(sale);
    setCart([]);
    setAmountPaid('');
    setMobileMoneyTxId('');
    setCustomerName('');
    setCustomerContact('');
    setPaymentMethod('cash');
    handleRefreshProducts();
    onSaleComplete();
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 h-full items-start relative">
      {/* Toast Notification Overlay (Fast Bulk Scanning Non-Blocking HUD) */}
      <AnimatePresence>
        {toast && (
          <motion.div
            initial={{ opacity: 0, y: -20, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -20, scale: 0.95 }}
            className="fixed top-6 left-1/2 -translate-x-1/2 z-[9999] pointer-events-none"
          >
            <div className={`px-5 py-3 rounded-xl shadow-2xl border flex items-center gap-2.5 font-display text-xs font-bold tracking-wide uppercase ${
              toast.type === 'success' 
                ? 'bg-slate-900 border-emerald-500/30 text-emerald-400' 
                : toast.type === 'error'
                ? 'bg-slate-900 border-rose-500/30 text-rose-400'
                : 'bg-slate-900 border-amber-500/30 text-amber-400'
            }`}>
              <span className={`h-2 w-2 rounded-full animate-pulse ${
                toast.type === 'success' 
                  ? 'bg-emerald-400' 
                  : toast.type === 'error'
                  ? 'bg-rose-400'
                  : 'bg-amber-400'
              }`}></span>
              {toast.message}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Commodities Selection Panel (Left 8 Columns) */}
      <div className="lg:col-span-8 bg-white rounded-2xl border border-slate-100 p-6 shadow-sm flex flex-col h-[calc(100vh-160px)] min-h-[500px]">
        
        {/* Dynamic Store Alerts (Visible to all staff) */}
        {(lowStockItems.length > 0 || expiredItems.length > 0 || nearExpiryItems.length > 0) && (
          <div className="mb-4 bg-rose-50 border border-rose-100 rounded-xl p-3 text-xs text-rose-800 space-y-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <AlertTriangle size={15} className="text-rose-600 animate-pulse shrink-0" />
                <span className="font-bold font-display uppercase tracking-wider text-[10px]">
                  Store Alert Monitor: {lowStockItems.length + expiredItems.length + nearExpiryItems.length} Warnings Active
                </span>
              </div>
              <button
                type="button"
                onClick={() => setShowNotificationDetails(!showNotificationDetails)}
                className="text-[9px] font-bold text-rose-700 bg-rose-100 hover:bg-rose-200/80 px-2.5 py-1 rounded transition-all shrink-0"
              >
                {showNotificationDetails ? 'Hide Details' : 'View Affected Commodities'}
              </button>
            </div>

            {showNotificationDetails && (
              <div className="pt-2 border-t border-rose-200/50 max-h-40 overflow-y-auto space-y-1 text-[10px] font-sans divide-y divide-rose-100">
                {expiredItems.map(p => (
                  <div key={p.id} className="py-1 flex justify-between items-center text-rose-700 gap-2">
                    <span className="truncate">❌ <b>[EXPIRED]</b> {p.name} ({p.sku})</span>
                    <span className="font-mono text-[9px] font-bold bg-rose-200 text-rose-800 px-1.5 py-0.5 rounded shrink-0">Expired: {p.expirationDate}</span>
                  </div>
                ))}
                {nearExpiryItems.map(p => (
                  <div key={p.id} className="py-1 flex justify-between items-center text-amber-800 gap-2">
                    <span className="truncate">⚠️ <b>[NEAR EXPIRED]</b> {p.name} ({p.sku})</span>
                    <span className="font-mono text-[9px] font-bold bg-amber-100 text-amber-900 px-1.5 py-0.5 rounded shrink-0">Expires: {p.expirationDate}</span>
                  </div>
                ))}
                {lowStockItems.map(p => (
                  <div key={p.id} className="py-1 flex justify-between items-center text-slate-700 gap-2">
                    <span className="truncate">📉 <b>[REPLENISH]</b> {p.name} ({p.sku})</span>
                    <span className="font-mono text-[9px] font-bold bg-slate-200 text-slate-800 px-1.5 py-0.5 rounded shrink-0">Stock: {p.currentStock} left (Min: {p.minStockLevel})</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Barcode Scanner Engine Status and Simulator */}
        <div className="mb-4 bg-slate-50 border border-slate-200/60 rounded-xl p-3 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-xs">
          <div className="flex items-center gap-3">
            <span className="flex h-2 w-2 relative">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </span>
            <span className="font-display font-bold text-slate-700">
              Hardware Scanner Engine: <span className="text-emerald-600 font-black">ACTIVE & LISTENING</span>
            </span>
            <button
              type="button"
              onClick={() => setShowHardwareConfig(!showHardwareConfig)}
              className={`px-2.5 py-1 rounded-lg text-[10px] font-display font-semibold border flex items-center gap-1.5 transition-all ${
                showHardwareConfig 
                  ? 'bg-indigo-50 border-indigo-200 text-indigo-700'
                  : 'bg-white border-slate-200 hover:bg-slate-50 text-slate-600 shadow-sm'
              }`}
            >
              <Sliders size={10} />
              {showHardwareConfig ? 'Hide Printer Config' : 'Configure Printers'}
            </button>
          </div>
          <div className="flex items-center gap-2 w-full sm:w-auto">
            <span className="text-slate-400 text-[10px] font-sans">No physical scanner? Test here:</span>
            <input
              type="text"
              placeholder="Type SKU & Press Enter to Scan"
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  const inputVal = (e.target as HTMLInputElement).value.trim().toUpperCase();
                  const prod = products.find(p => p.sku.toUpperCase() === inputVal);
                  if (prod) {
                    addToCart(prod);
                    // Play a subtle success audio beep
                    try {
                      const audioCtx = new (window.AudioContext || (window as any).webkitAudioContext)();
                      const oscillator = audioCtx.createOscillator();
                      const gainNode = audioCtx.createGain();
                      oscillator.connect(gainNode);
                      gainNode.connect(audioCtx.destination);
                      oscillator.type = 'sine';
                      oscillator.frequency.setValueAtTime(1000, audioCtx.currentTime);
                      gainNode.gain.setValueAtTime(0.08, audioCtx.currentTime);
                      oscillator.start();
                      oscillator.stop(audioCtx.currentTime + 0.1);
                    } catch (err) {}
                    showToast(`✅ Simulated Scan Success: "${prod.name}" added to cart!`, 'success');
                  } else {
                    showToast(`❌ SKU "${inputVal}" not found in commodity catalog.`, 'error');
                  }
                  (e.target as HTMLInputElement).value = '';
                }
              }}
              className="bg-white border border-slate-200 rounded-lg px-2 py-1 text-[11px] font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 text-slate-800 w-full sm:w-48 placeholder-slate-400"
            />
          </div>
        </div>

        {/* Collapsible Hardware Panel */}
        <AnimatePresence>
          {showHardwareConfig && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              className="overflow-hidden mb-4"
            >
              <HardwareHub />
            </motion.div>
          )}
        </AnimatePresence>

        {/* Search & Category Header */}
        <div className="flex flex-col md:flex-row gap-4 mb-6">
          <div className="relative flex-1">
            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
            <input
              type="text"
              placeholder="Search commodity by name or SKU..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full bg-slate-50 border border-slate-200 rounded-xl py-2.5 pl-11 pr-4 text-sm font-sans placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 transition-all text-slate-800"
            />
          </div>
          <div className="flex gap-1.5 overflow-x-auto pb-1 no-scrollbar max-w-full md:max-w-md">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3.5 py-2 rounded-xl text-xs font-display font-medium whitespace-nowrap transition-all ${
                  selectedCategory === cat
                    ? 'bg-slate-900 text-white shadow-sm'
                    : 'bg-slate-50 hover:bg-slate-100 text-slate-600 border border-slate-200/50'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>

        {/* Commodity Grid */}
        <div className="flex-1 overflow-y-auto pr-1">
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
            {filteredProducts.map(p => {
              const inCart = cart.find(item => item.product.id === p.id);
              const remainingStock = p.currentStock - (inCart?.quantity || 0);
              const isLow = p.currentStock <= p.minStockLevel;
              const expired = isProductExpired(p);
              const nearExpiry = isProductNearExpiry(p);

              return (
                <div
                  key={p.id}
                  onClick={() => remainingStock > 0 && addToCart(p)}
                  className={`group border rounded-xl p-4 transition-all relative flex flex-col justify-between ${
                    expired 
                      ? 'bg-rose-50/50 border-rose-200/80 hover:border-rose-400 hover:shadow-md cursor-pointer'
                      : remainingStock <= 0 
                      ? 'bg-slate-50 border-slate-100 opacity-60 cursor-not-allowed'
                      : 'bg-white border-slate-150 hover:border-indigo-500/40 hover:shadow-md cursor-pointer'
                  }`}
                >
                  <div>
                    {/* Expiry alerts */}
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-[10px] font-mono text-slate-400 font-medium">{p.sku}</span>
                      {expired && (
                        <span className="bg-red-600 text-white text-[9px] px-1.5 py-0.5 rounded-md font-bold flex items-center gap-1">
                          <AlertTriangle size={10} /> Expired
                        </span>
                      )}
                      {!expired && nearExpiry && (
                        <span className="bg-amber-100 text-amber-800 text-[9px] px-1.5 py-0.5 rounded-md font-bold flex items-center gap-0.5">
                          <CalendarRange size={10} /> Expiring
                        </span>
                      )}
                    </div>

                    <h3 className="font-display font-semibold text-slate-800 text-sm group-hover:text-indigo-600 transition-colors line-clamp-2">
                      {p.name}
                    </h3>
                    <p className="text-xs text-slate-400 mt-1">{p.category}</p>
                  </div>

                  <div className="mt-4 flex items-end justify-between pt-2 border-t border-slate-50">
                    <div>
                      <p className="text-xs text-slate-400">Retail Price</p>
                      <p className="font-mono font-semibold text-slate-950 text-sm">
                        shs {p.sellingPrice.toLocaleString()}
                      </p>
                    </div>

                    <div className="text-right">
                      <p className="text-[10px] text-slate-400">Remaining</p>
                      <span className={`font-mono text-xs font-bold ${
                        remainingStock <= 0 
                          ? 'text-red-500' 
                          : remainingStock <= p.minStockLevel 
                          ? 'text-amber-500' 
                          : 'text-emerald-600'
                      }`}>
                        {remainingStock <= 0 ? 'OUT' : `${remainingStock} left`}
                      </span>
                    </div>
                  </div>

                  {/* Quantity selected banner */}
                  {inCart && (
                    <div className="absolute top-2 right-2 bg-indigo-600 text-white h-5 px-1.5 rounded-full text-[10px] font-bold flex items-center justify-center shadow-sm">
                      Selected: {inCart.quantity}
                    </div>
                  )}
                </div>
              );
            })}

            {filteredProducts.length === 0 && (
              <div className="col-span-full py-12 flex flex-col items-center justify-center text-slate-400">
                <ShoppingBagIcon className="w-10 h-10 mb-2 stroke-slate-300" />
                <p className="font-display font-medium text-sm">No matching commodities found</p>
                <p className="text-xs">Try adjusting your category filter or search query</p>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* POS Cart & Payment Panel (Right 4 Columns) */}
      <div className="lg:col-span-4 bg-white rounded-2xl border border-slate-100 shadow-sm flex flex-col h-[calc(100vh-160px)] min-h-[500px]">
        {/* Cart Title */}
        <div className="p-5 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="p-2 bg-indigo-50 text-indigo-600 rounded-lg">
              <ShoppingCart size={18} />
            </div>
            <div>
              <h2 className="font-display font-semibold text-slate-800 text-sm">Active Checkout</h2>
              <p className="text-xs text-slate-400">{cart.reduce((sum, item) => sum + item.quantity, 0)} items</p>
            </div>
          </div>
          {cart.length > 0 && (
            <button
              onClick={() => setCart([])}
              className="text-xs font-display font-medium text-slate-400 hover:text-red-500 transition-colors"
            >
              Clear Cart
            </button>
          )}
        </div>

        {/* Cart List */}
        <div className="flex-1 overflow-y-auto p-5 space-y-4">
          <AnimatePresence initial={false}>
            {cart.map(item => (
              <motion.div
                key={item.product.id}
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                exit={{ opacity: 0, height: 0 }}
                className="flex items-center justify-between gap-2 border-b border-slate-50 pb-3 last:border-0"
              >
                <div className="flex-1 min-w-0">
                  <h4 className="font-display font-medium text-slate-800 text-xs truncate">{item.product.name}</h4>
                  <p className="font-mono text-[10px] text-slate-400 mt-0.5">
                    shs {item.product.sellingPrice.toLocaleString()} &times; {item.quantity}
                  </p>
                </div>

                <div className="flex items-center gap-1.5 bg-slate-50 border border-slate-200/40 rounded-lg p-0.5">
                  <button
                    onClick={() => updateQuantity(item.product.id, -1)}
                    className="p-1 hover:bg-white rounded text-slate-500 hover:text-slate-800 transition-colors"
                  >
                    <Minus size={10} />
                  </button>
                  <span className="font-mono font-semibold text-slate-800 text-xs px-1">{item.quantity}</span>
                  <button
                    onClick={() => updateQuantity(item.product.id, 1)}
                    disabled={item.quantity >= item.product.currentStock}
                    className="p-1 hover:bg-white rounded text-slate-500 hover:text-slate-800 transition-colors disabled:opacity-30"
                  >
                    <Plus size={10} />
                  </button>
                </div>

                <button
                  onClick={() => removeFromCart(item.product.id)}
                  className="p-1 hover:bg-red-50 rounded-lg text-slate-400 hover:text-red-500 transition-colors"
                >
                  <Trash2 size={12} />
                </button>
              </motion.div>
            ))}
          </AnimatePresence>

          {cart.length === 0 && (
            <div className="h-full flex flex-col items-center justify-center text-slate-300 py-12">
              <ShoppingCart size={32} strokeWidth={1.5} className="mb-2" />
              <p className="text-xs font-display">Basket is empty</p>
              <p className="text-[10px] text-center mt-1">Select products from the catalog to add them here</p>
            </div>
          )}
        </div>

        {/* Calculations & Cash Checkout Form */}
        {cart.length > 0 && (
          <form onSubmit={handleCheckout} className="p-5 border-t border-slate-100 bg-slate-50 rounded-b-2xl space-y-4">
            {/* Totals */}
            <div className="space-y-1.5 text-xs text-slate-600">
              <div className="flex justify-between">
                <span>Subtotal:</span>
                <span className="font-mono">shs {cartTotal.toLocaleString()}</span>
              </div>
              <div className="flex justify-between font-bold text-slate-800 text-sm">
                <span>Total Due:</span>
                <span className="font-mono text-slate-950">shs {cartTotal.toLocaleString()}</span>
              </div>
            </div>

            {/* Payment Method Selector */}
            <div>
              <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1.5">
                Payment Channel
              </label>
              <div className="grid grid-cols-4 gap-2">
                {(['cash', 'mobile_money', 'card', 'partial'] as const).map(method => (
                  <button
                    key={method}
                    type="button"
                    onClick={() => setPaymentMethod(method)}
                    className={`py-2 rounded-xl text-[10px] font-display font-medium border transition-all flex flex-col items-center justify-center gap-1 ${
                      paymentMethod === method
                        ? 'bg-slate-900 border-slate-900 text-white shadow-sm'
                        : 'bg-white border-slate-200 hover:bg-slate-50 text-slate-600'
                    }`}
                  >
                    {method === 'cash' && <span>💵 Cash</span>}
                    {method === 'mobile_money' && <span>📱 Mobile</span>}
                    {method === 'card' && <span>💳 Card</span>}
                    {method === 'partial' && <span>🧾 Loan</span>}
                  </button>
                ))}
              </div>
            </div>

            {/* Partial / loan sale: cash now + customer + pledge date */}
            {paymentMethod === 'partial' && (
              <div className="space-y-3 rounded-xl border border-amber-200 bg-amber-50/60 p-3">
                <div className="grid grid-cols-2 gap-3 items-start">
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-500 uppercase tracking-wider mb-1">
                      Cash Paid Now
                    </label>
                    <input
                      type="number"
                      min={0}
                      max={cartTotal}
                      placeholder="shs 0"
                      value={amountPaid}
                      onChange={(e) => setAmountPaid(e.target.value === '' ? '' : Number(e.target.value))}
                      className="w-full bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono placeholder-slate-300 focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-500 text-slate-800"
                    />
                  </div>
                  <div>
                    <p className="text-[10px] font-display font-semibold text-slate-500 uppercase tracking-wider mb-1">
                      Balance on Loan
                    </p>
                    <p className="font-mono text-sm font-bold text-rose-600 bg-white border border-slate-200/50 rounded-xl px-3 py-2">
                      shs {loanAmount.toLocaleString()}
                    </p>
                  </div>
                </div>
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-500 uppercase tracking-wider mb-1">
                    Customer Name
                  </label>
                  <input
                    type="text"
                    placeholder="Full name"
                    value={customerName}
                    onChange={(e) => setCustomerName(e.target.value)}
                    className="w-full bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-500 text-slate-800"
                  />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-500 uppercase tracking-wider mb-1">
                      Contact (10 digits)
                    </label>
                    <input
                      type="tel"
                      inputMode="numeric"
                      maxLength={10}
                      placeholder="0700000000"
                      value={customerContact}
                      onChange={(e) => setCustomerContact(e.target.value.replace(/\D/g, '').slice(0, 10))}
                      className="w-full bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-500 text-slate-800"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-500 uppercase tracking-wider mb-1">
                      Pledged Repayment
                    </label>
                    <input
                      type="date"
                      value={pledgeDate}
                      onChange={(e) => setPledgeDate(e.target.value)}
                      className="w-full bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-amber-500/20 focus:border-amber-500 text-slate-800"
                    />
                  </div>
                </div>
              </div>
            )}

            {/* Cash Paid input */}
            {paymentMethod === 'cash' && (
              <div className="grid grid-cols-2 gap-3 items-center">
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Cash Received
                  </label>
                  <input
                    type="number"
                    required
                    min={cartTotal}
                    placeholder={`shs ${cartTotal}`}
                    value={amountPaid}
                    onChange={(e) => setAmountPaid(e.target.value === '' ? '' : Number(e.target.value))}
                    className="w-full bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono placeholder-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                </div>
                <div>
                  <p className="text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Change Due
                  </p>
                  <p className="font-mono text-sm font-bold text-emerald-600 bg-white border border-slate-200/50 rounded-xl px-3 py-2">
                    shs {changeDue.toLocaleString()}
                  </p>
                </div>
              </div>
            )}

            {/* Mobile Money Transaction ID */}
            {paymentMethod === 'mobile_money' && (
              <div className="space-y-1">
                <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                  Mobile Money Transaction ID (e.g. Reference/TxID)
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. PP2607031122, MTN-8910..."
                  value={mobileMoneyTxId}
                  onChange={(e) => setMobileMoneyTxId(e.target.value)}
                  className="w-full bg-white border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 uppercase"
                />
              </div>
            )}

            {/* Complete Transaction */}
            <button
              type="submit"
              className="w-full bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl py-3 font-display font-semibold text-xs tracking-wider uppercase transition-all shadow-md hover:shadow-lg flex items-center justify-center gap-1.5"
            >
              <CreditCard size={14} />
              Complete POS & Print
            </button>
          </form>
        )}
      </div>

      {/* Pop up receipt */}
      {completedSale && (
        <ThermalReceipt
          sale={completedSale}
          onClose={() => setCompletedSale(null)}
        />
      )}
    </div>
  );
};

const ShoppingBagIcon = (props: React.SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    {...props}
  >
    <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
    <path d="M3 6h18" />
    <path d="M16 10a4 4 0 0 1-8 0" />
  </svg>
);

export default POSView;
