import React, { useState, useMemo } from 'react';
import { Product, StockTransaction } from '../types';
import localDB from '../utils/localDB';
import { Plus, Search, Edit2, Archive, AlertTriangle, ArrowUpRight, ArrowDownRight, Package, Save, CheckCircle2, Sparkles, Printer, Tag, Download, Trash2, Settings } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { Barcode } from './Barcode';
import { hardwareManager } from '../utils/hardware';

interface InventoryViewProps {
  onRefresh: () => void;
}

export const InventoryView: React.FC<InventoryViewProps> = ({ onRefresh }) => {
  const [products, setProducts] = useState<Product[]>(() => localDB.getProducts());
  const [transactions, setTransactions] = useState<StockTransaction[]>(() => localDB.getTransactions());
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [activeTab, setActiveTab] = useState<'catalog' | 'ledger'>('catalog');

  // Dynamic Categories from localDB
  const [dbCategories, setDbCategories] = useState<string[]>(() => localDB.getCategories());

  // Deleting a commodity outright is a top-manager-only privilege.
  const isTopManager = localDB.getSession().role === 'top_manager';

  // Form states for creating/editing product
  const [showProductModal, setShowProductModal] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  const [formData, setFormData] = useState({
    name: '',
    sku: '',
    category: 'Grains & Pasta',
    buyingPrice: 0,
    wholesalePrice: 0, // limit price — the POS floor
    sellingPrice: 0,
    currentStock: 0,
    minStockLevel: 5,
    expirationDate: ''
  });

  // Form states for quick restocking (with batching option)
  const [showRestockModal, setShowRestockModal] = useState(false);
  const [restockProduct, setRestockProduct] = useState<Product | null>(null);
  const [restockQty, setRestockQty] = useState<number | ''>('');
  const [restockBuyingPrice, setRestockBuyingPrice] = useState<number | ''>('');
  const [restockExpirationDate, setRestockExpirationDate] = useState<string>('');
  const [createNewBatch, setCreateNewBatch] = useState<boolean>(false);

  // Form states for dynamic category manager
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [newCatName, setNewCatName] = useState('');
  const [editingCatName, setEditingCatName] = useState<string | null>(null);
  const [editingCatValue, setEditingCatValue] = useState('');

  // Form states for quick price adjustments
  const [showPriceModal, setShowPriceModal] = useState(false);
  const [priceProduct, setPriceProduct] = useState<Product | null>(null);
  const [quickSellingPrice, setQuickSellingPrice] = useState<number | ''>('');
  const [quickBuyingPrice, setQuickBuyingPrice] = useState<number | ''>('');

  // Non-blocking banner feedback
  const [notificationBanner, setNotificationBanner] = useState<{ type: 'success' | 'info'; message: string } | null>(null);

  // Form states for sticker/barcode printing
  const [showBarcodeModal, setShowBarcodeModal] = useState(false);
  const [barcodeProduct, setBarcodeProduct] = useState<Product | null>(null);
  const [stickerCount, setStickerCount] = useState<number>(12);
  const [showBranding, setShowBranding] = useState(true);
  const [showExpiryOnSticker, setShowExpiryOnSticker] = useState(true);
  const [customStickerPrice, setCustomStickerPrice] = useState<number | ''>('');
  const [stickerPrintStatus, setStickerPrintStatus] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  const handleOpenBarcodeModal = (p: Product) => {
    setBarcodeProduct(p);
    setStickerCount(12);
    setShowBranding(true);
    setShowExpiryOnSticker(!!p.expirationDate);
    setCustomStickerPrice(p.sellingPrice);
    setShowBarcodeModal(true);
    setStickerPrintStatus(null);
  };

  const handlePrintStickers = async () => {
    if (!barcodeProduct) return;
    const paired = hardwareManager.getPairedPrinter();
    setStickerPrintStatus(null);
    if (paired) {
      try {
        const priceVal = customStickerPrice === '' ? barcodeProduct.sellingPrice : customStickerPrice;
        for (let i = 0; i < stickerCount; i++) {
          const bytes = hardwareManager.generateStickerBytes(
            barcodeProduct,
            priceVal,
            showBranding,
            showExpiryOnSticker
          );
          await hardwareManager.printRawESCPOS(bytes);
        }
        setStickerPrintStatus({ 
          type: 'success', 
          message: `✅ Direct Hardware Print Success: Transmitted ${stickerCount} sticker label(s) to thermal printer!` 
        });
        setTimeout(() => {
          setShowBarcodeModal(false);
          setStickerPrintStatus(null);
        }, 2200);
      } catch (err: any) {
        setStickerPrintStatus({ 
          type: 'error', 
          message: `⚠️ Direct hardware print failed: ${err.message}\nTrying system print fallback...` 
        });
        setTimeout(() => {
          try {
            window.print();
          } catch (printErr) {
            setStickerPrintStatus({
              type: 'error',
              message: '⚠️ Sandboxed browser blocked printing. Click "Export & Print File" below!'
            });
          }
        }, 1200);
      }
    } else {
      try {
        window.print();
        setStickerPrintStatus({
          type: 'success',
          message: 'Standard print dialog requested. If blocked by sandbox, click "Export & Print File" instead.'
        });
      } catch (printErr) {
        setStickerPrintStatus({
          type: 'error',
          message: '⚠️ Sandboxed browser blocked printing. Click "Export & Print File" below!'
        });
      }
    }
  };

  const exportStickersHTML = () => {
    if (!barcodeProduct) return;
    const finalPrice = customStickerPrice === '' ? barcodeProduct.sellingPrice : customStickerPrice;
    
    const htmlContent = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Stickers_${barcodeProduct.sku}</title>
  <style>
    body {
      margin: 0;
      padding: 10px;
      font-family: system-ui, -apple-system, sans-serif;
      background: white;
    }
    .sticker-container {
      display: flex;
      flex-wrap: wrap;
      gap: 15px;
    }
    .sticker {
      width: 50mm;
      height: 30mm;
      border: 1px dashed #ccc;
      padding: 8px;
      box-sizing: border-box;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .brand {
      text-align: center;
      font-weight: 900;
      text-transform: uppercase;
      font-size: 8px;
      border-bottom: 1px dashed #ddd;
      padding-bottom: 2px;
      margin-bottom: 4px;
    }
    .title {
      font-weight: 800;
      font-size: 10px;
      text-transform: uppercase;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .cat {
      font-size: 7px;
      color: #666;
      font-family: monospace;
    }
    .barcode-wrapper {
      text-align: center;
      margin: 4px 0;
    }
    .sku {
      font-size: 8px;
      font-family: monospace;
      letter-spacing: 2px;
    }
    .footer {
      display: flex;
      justify-content: space-between;
      align-items: flex-end;
      border-top: 1px dashed #ddd;
      padding-top: 2px;
      margin-top: 2px;
    }
    .expiry {
      font-size: 7px;
      color: #666;
    }
    .price {
      font-size: 12px;
      font-family: monospace;
      font-weight: 900;
    }
    @media print {
      body { padding: 0; }
      .sticker { border: none; }
    }
  </style>
</head>
<body onload="window.print()">
  <div class="sticker-container">
    \${Array.from({ length: ${stickerCount} }).map(() => \`
      <div class="sticker">
        \${${showBranding} ? \`<div class="brand">APEX SUPERMARKET</div>\` : ''}
        <div>
          <div class="title">\${"${barcodeProduct.name.replace(/"/g, '\\"')}"}</div>
          <div class="cat">CAT: \${"${barcodeProduct.category}"}</div>
        </div>
        <div class="barcode-wrapper">
          <svg width="140" height="20" viewBox="0 0 140 20" xmlns="http://www.w3.org/2000/svg">
            <rect width="140" height="20" fill="#fff"/>
            \${Array.from({ length: 28 }).map((_, idx) => {
              const width = idx % 3 === 0 ? 3 : idx % 2 === 0 ? 1 : 2;
              const fill = idx % 7 === 0 ? '#fff' : '#000';
              const x = idx * 4.5;
              return \`<rect x="\${x}" y="0" width="\${width}" height="20" fill="\${fill}"/>\`;
            }).join('')}
          </svg>
          <div class="sku">\${"${barcodeProduct.sku}"}</div>
        </div>
        <div class="footer">
          <div class="expiry">
            \${${showExpiryOnSticker && !!barcodeProduct.expirationDate} ? \`EXP: \${"${barcodeProduct.expirationDate}"}\` : ''}
            <div>LOC: MAIN STK</div>
          </div>
          <div class="price">shs \${(${finalPrice}).toLocaleString()}</div>
        </div>
      </div>
    \`).join('')}
  </div>
</body>
</html>`;

    const blob = new Blob([htmlContent], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `stickers_${barcodeProduct.sku}.html`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    setStickerPrintStatus({
      type: 'success',
      message: '✅ File downloaded! Double click the stickers file to print instantly.'
    });
  };

  const handleRefresh = () => {
    setProducts(localDB.getProducts());
    setTransactions(localDB.getTransactions());
    setDbCategories(localDB.getCategories());
    onRefresh();
  };

  const categories = useMemo(() => {
    return ['All', ...dbCategories];
  }, [dbCategories]);

  const filteredProducts = useMemo(() => {
    return products.filter(p => {
      const matchesSearch = p.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
                            p.sku.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesCategory = selectedCategory === 'All' || p.category === selectedCategory;
      return matchesSearch && matchesCategory;
    });
  }, [products, searchQuery, selectedCategory]);

  const handleOpenCreateModal = () => {
    setEditingProduct(null);
    const initialCategory = dbCategories[0] || 'Grains & Pasta';
    setFormData({
      name: '',
      sku: '',
      category: initialCategory,
      buyingPrice: 0,
      wholesalePrice: 0,
      sellingPrice: 0,
      currentStock: 0,
      minStockLevel: 5,
      expirationDate: ''
    });
    setShowProductModal(true);
  };

  const handleOpenEditModal = (p: Product) => {
    setEditingProduct(p);
    setFormData({
      name: p.name,
      sku: p.sku,
      category: p.category,
      buyingPrice: p.buyingPrice,
      wholesalePrice: p.wholesalePrice ?? p.retailPrice ?? p.sellingPrice,
      sellingPrice: p.sellingPrice,
      currentStock: p.currentStock,
      minStockLevel: p.minStockLevel,
      expirationDate: p.expirationDate || ''
    });
    setShowProductModal(true);
  };

  const triggerAutoSKU = () => {
    const catCode = formData.category
      ? formData.category.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 3)
      : 'GEN';
    const cleanName = formData.name
      ? formData.name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase()
      : 'PRD';
    const randomNum = Math.floor(100000 + Math.random() * 900000); // 6-digit random number
    const generated = `${catCode}-${cleanName}-${randomNum}`;
    setFormData(prev => ({ ...prev, sku: generated }));
  };

  const handleSaveProduct = (e: React.FormEvent) => {
    e.preventDefault();

    const buying = Number(formData.buyingPrice);
    const limit = Number(formData.wholesalePrice);
    const selling = Number(formData.sellingPrice);
    // Price integrity: cost ≤ limit ≤ selling. Blocks saving a product that
    // could be sold at or below cost, which corrupts POS profit/revenue figures.
    if (buying <= 0) {
      alert('⚠️ Buying cost must be greater than 0.');
      return;
    }
    if (limit < buying) {
      alert(`⚠️ Limit price cannot be below the buying cost (shs ${buying.toLocaleString()}).`);
      return;
    }
    if (selling < limit) {
      alert(`⚠️ Selling price cannot be below the limit price (shs ${limit.toLocaleString()}).`);
      return;
    }

    let finalSku = formData.sku.trim();
    if (!finalSku) {
      const catCode = formData.category
        ? formData.category.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 3)
        : 'GEN';
      const cleanName = formData.name
        ? formData.name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase()
        : 'PRD';
      const randomNum = Math.floor(100000 + Math.random() * 900000);
      finalSku = `${catCode}-${cleanName}-${randomNum}`;
    }

    if (editingProduct) {
      // Update existing
      const updated: Product = {
        ...editingProduct,
        name: formData.name,
        sku: finalSku,
        category: formData.category,
        buyingPrice: buying,
        wholesalePrice: limit,
        retailPrice: selling,
        sellingPrice: selling,
        currentStock: Number(formData.currentStock),
        minStockLevel: Number(formData.minStockLevel),
        expirationDate: formData.expirationDate || null
      };
      localDB.updateProduct(updated);
    } else {
      // Create new
      localDB.addProduct({
        name: formData.name,
        sku: finalSku,
        category: formData.category,
        buyingPrice: buying,
        wholesalePrice: limit,
        retailPrice: selling,
        sellingPrice: selling,
        currentStock: Number(formData.currentStock),
        minStockLevel: Number(formData.minStockLevel),
        expirationDate: formData.expirationDate || null
      });
    }

    setShowProductModal(false);
    handleRefresh();
  };

  const handleOpenRestockModal = (p: Product) => {
    setRestockProduct(p);
    setRestockQty('');
    setRestockBuyingPrice(p.buyingPrice);
    setRestockExpirationDate(p.expirationDate || '');
    setCreateNewBatch(false);
    setShowRestockModal(true);
  };

  const handleSaveRestock = (e: React.FormEvent) => {
    e.preventDefault();
    if (!restockProduct || restockQty === '') return;

    const res = localDB.restockProduct(
      restockProduct.id, 
      Number(restockQty), 
      restockBuyingPrice !== '' ? Number(restockBuyingPrice) : undefined,
      restockExpirationDate || null,
      createNewBatch
    );

    setShowRestockModal(false);
    handleRefresh();

    if (res && res.type === 'new_batch') {
      setNotificationBanner({
        type: 'success',
        message: `📦 Created separate batch: "${res.product.name}" with SKU "${res.product.sku}" and Expiration Date: "${res.product.expirationDate}".`
      });
      setTimeout(() => setNotificationBanner(null), 6000);
    } else {
      setNotificationBanner({
        type: 'success',
        message: `✅ Successfully replenished ${Number(restockQty).toLocaleString()} units of "${restockProduct.name}"!`
      });
      setTimeout(() => setNotificationBanner(null), 3500);
    }
  };

  // Category management handlers
  const handleAddCategory = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = newCatName.trim();
    if (!trimmed) return;
    localDB.addCategory(trimmed);
    setNewCatName('');
    handleRefresh();
    setNotificationBanner({
      type: 'success',
      message: `📁 Created new category: "${trimmed}"`
    });
  };

  const handleStartEditCategory = (cat: string) => {
    setEditingCatName(cat);
    setEditingCatValue(cat);
  };

  const handleSaveEditCategory = (oldName: string) => {
    const trimmed = editingCatValue.trim();
    if (!trimmed || trimmed === oldName) {
      setEditingCatName(null);
      return;
    }
    localDB.editCategory(oldName, trimmed);
    setEditingCatName(null);
    handleRefresh();
    setNotificationBanner({
      type: 'success',
      message: `✏️ Renamed category from "${oldName}" to "${trimmed}"`
    });
  };

  const handleDeleteCategory = (cat: string) => {
    if (dbCategories.length <= 1) {
      alert("⚠️ You must have at least one category remaining.");
      return;
    }
    localDB.deleteCategory(cat);
    handleRefresh();
    setNotificationBanner({
      type: 'info',
      message: `🗑️ Deleted category "${cat}". Any products in it were re-assigned to "${localDB.getCategories()[0]}".`
    });
  };

  // Commodity deletion (Top Manager only). Routed through the authoritative endpoint
  // so the record is tombstoned — a plain local removal reappears on the next sync.
  const handleDeleteProduct = async (p: Product) => {
    if (!isTopManager) return;
    if (!window.confirm(`Permanently delete "${p.name}" from the catalog? This removes it from the cloud database for every terminal and cannot be undone.`)) {
      return;
    }
    await localDB.deleteProduct(p.id);
    handleRefresh();
    setNotificationBanner({
      type: 'info',
      message: `🗑️ Deleted commodity "${p.name}". The removal has been pushed to the cloud database.`
    });
  };

  // Quick price adjustment handlers
  const handleSaveQuickPrice = (e: React.FormEvent) => {
    e.preventDefault();
    if (!priceProduct || quickSellingPrice === '') return;
    const selling = Number(quickSellingPrice);
    const buying = quickBuyingPrice !== '' ? Number(quickBuyingPrice) : priceProduct.buyingPrice;
    const limit = priceProduct.wholesalePrice ?? priceProduct.retailPrice ?? priceProduct.sellingPrice ?? buying;
    // Keep the cost ≤ limit ≤ selling invariant intact.
    if (selling < limit) {
      alert(`⚠️ Selling price cannot be below the limit price (shs ${Number(limit).toLocaleString()}).`);
      return;
    }
    if (limit < buying) {
      alert(`⚠️ Buying cost (shs ${buying.toLocaleString()}) is above the limit price — edit the product to fix its limit first.`);
      return;
    }
    const updated: Product = {
      ...priceProduct,
      sellingPrice: selling,
      retailPrice: selling,
      buyingPrice: buying
    };
    localDB.updateProduct(updated);
    setShowPriceModal(false);
    handleRefresh();
    setNotificationBanner({
      type: 'success',
      message: `💰 Updated prices for ${priceProduct.name}! New Selling: shs ${Number(quickSellingPrice).toLocaleString()}`
    });
    setTimeout(() => setNotificationBanner(null), 3000);
  };

  return (
    <div className="space-y-6">
      {/* Dynamic Feedback Toast Banner */}
      <AnimatePresence>
        {notificationBanner && (
          <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            className="bg-emerald-600 text-white p-4 rounded-xl shadow-lg flex items-center gap-2.5 text-xs font-semibold"
          >
            <CheckCircle2 size={16} className="shrink-0" />
            <div className="flex-1">{notificationBanner.message}</div>
            <button 
              onClick={() => setNotificationBanner(null)} 
              className="text-white/80 hover:text-white uppercase text-[10px] tracking-wider"
            >
              Dismiss
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Header Tabs switcher & Trigger Action */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-4 rounded-2xl border border-slate-100 shadow-sm">
        <div className="flex bg-slate-50 border border-slate-200/50 p-1 rounded-xl">
          <button
            onClick={() => setActiveTab('catalog')}
            className={`px-4 py-1.5 rounded-lg text-xs font-display font-semibold transition-all ${
              activeTab === 'catalog'
                ? 'bg-white text-slate-900 shadow-sm'
                : 'text-slate-500 hover:text-slate-800'
            }`}
          >
            Commodity Catalog
          </button>
          <button
            onClick={() => setActiveTab('ledger')}
            className={`px-4 py-1.5 rounded-lg text-xs font-display font-semibold transition-all ${
              activeTab === 'ledger'
                ? 'bg-white text-slate-900 shadow-sm'
                : 'text-slate-500 hover:text-slate-800'
            }`}
          >
            Replenishment Ledger
          </button>
        </div>

        {activeTab === 'catalog' && (
          <div className="flex gap-2">
            <button
              onClick={() => setShowCategoryModal(true)}
              className="bg-white hover:bg-slate-50 border border-slate-200 text-slate-700 rounded-xl px-4 py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-sm hover:shadow flex items-center gap-1.5"
            >
              <Tag size={14} className="text-slate-500" />
              Manage Categories
            </button>
            <button
              onClick={handleOpenCreateModal}
              className="bg-slate-900 hover:bg-slate-800 text-white rounded-xl px-4 py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-sm hover:shadow flex items-center gap-1.5"
            >
              <Plus size={14} />
              Add Commodity
            </button>
          </div>
        )}
      </div>

      {activeTab === 'catalog' ? (
        <div className="bg-white rounded-2xl border border-slate-100 shadow-sm overflow-hidden p-6 space-y-6">
          {/* Filters & Search */}
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
              <input
                type="text"
                placeholder="Search catalog by name, SKU, or category..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl py-2.5 pl-11 pr-4 text-xs font-sans placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
              />
            </div>
            <div className="flex gap-1 overflow-x-auto pb-1 max-w-full no-scrollbar">
              {categories.map(cat => (
                <button
                  key={cat}
                  onClick={() => setSelectedCategory(cat)}
                  className={`px-3 py-2 rounded-xl text-[10px] font-display font-semibold whitespace-nowrap border transition-all ${
                    selectedCategory === cat
                      ? 'bg-slate-900 border-slate-900 text-white shadow-sm'
                      : 'bg-white border-slate-200 hover:bg-slate-50 text-slate-600'
                  }`}
                >
                  {cat}
                </button>
              ))}
            </div>
          </div>

          {/* Table representing stock, buying cost, retail pricing */}
          <div className="overflow-x-auto border border-slate-100 rounded-xl">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-slate-50 text-slate-400 font-display font-bold text-[10px] tracking-wider uppercase border-b border-slate-100">
                  <th className="py-4.5 px-5">Sku / Name</th>
                  <th className="py-4.5 px-5">Category</th>
                  <th className="py-4.5 px-5 text-right">Buying Price</th>
                  <th className="py-4.5 px-5 text-right">Selling Price</th>
                  <th className="py-4.5 px-5 text-center">Remaining Stock</th>
                  <th className="py-4.5 px-5 text-center">Expiration Date</th>
                  <th className="py-4.5 px-5 text-center">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 text-slate-700 text-xs font-medium">
                {filteredProducts.map(p => {
                  const isLow = p.currentStock <= p.minStockLevel;
                  const isExpired = p.expirationDate && new Date(p.expirationDate) <= new Date('2026-07-02');

                  return (
                    <tr key={p.id} className="hover:bg-slate-50/50 transition-colors">
                      <td className="py-4 px-5">
                        <div className="flex flex-col">
                          <span className="font-mono text-[9px] text-slate-400 font-medium uppercase">{p.sku}</span>
                          <span className="font-display font-semibold text-slate-800 mt-0.5">{p.name}</span>
                        </div>
                      </td>
                      <td className="py-4 px-5">
                        <span className="bg-slate-100 border border-slate-200/40 text-slate-600 px-2.5 py-1 rounded-lg text-[10px]">
                          {p.category}
                        </span>
                      </td>
                      <td className="py-4 px-5 text-right font-mono text-slate-500">
                        shs {p.buyingPrice.toLocaleString()}
                      </td>
                      <td className="py-4 px-5 text-right font-mono font-semibold text-slate-900">
                        shs {p.sellingPrice.toLocaleString()}
                      </td>
                      <td className="py-4 px-5 text-center">
                        <div className="flex flex-col items-center gap-1">
                          <span className={`font-mono font-bold ${
                            p.currentStock <= 0 
                              ? 'text-red-500' 
                              : isLow 
                              ? 'text-amber-500' 
                              : 'text-emerald-600'
                          }`}>
                            {p.currentStock.toLocaleString()} units
                          </span>
                          {isLow && (
                            <span className="text-[9px] font-display text-amber-500 font-semibold flex items-center gap-0.5">
                              <AlertTriangle size={10} /> low stock
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="py-4 px-5 text-center">
                        {p.expirationDate ? (
                          <div className="flex flex-col items-center">
                            <span className={`font-mono text-[10px] font-semibold ${isExpired ? 'text-red-500' : 'text-slate-500'}`}>
                              {p.expirationDate}
                            </span>
                            {isExpired && (
                              <span className="text-[9px] font-display font-bold text-red-500 uppercase mt-0.5">Expired</span>
                            )}
                          </div>
                        ) : (
                          <span className="text-slate-400">No Expiry Limit</span>
                        )}
                      </td>
                      <td className="py-4 px-5">
                        <div className="flex items-center justify-center gap-2">
                          <button
                            onClick={() => handleOpenRestockModal(p)}
                            className="bg-indigo-50 hover:bg-indigo-100 text-indigo-600 px-3 py-1.5 rounded-lg text-[10px] font-display font-semibold transition-colors flex items-center gap-1"
                          >
                            <Package size={12} />
                            Restock
                          </button>
                          <button
                            onClick={() => handleOpenBarcodeModal(p)}
                            className="p-1.5 border border-emerald-200 bg-emerald-50 hover:bg-emerald-100 text-emerald-600 rounded-lg transition-colors"
                            title="Print Barcode Stickers"
                          >
                            <Printer size={12} />
                          </button>
                          <button
                            onClick={() => {
                              setPriceProduct(p);
                              setQuickSellingPrice(p.sellingPrice);
                              setQuickBuyingPrice(p.buyingPrice);
                              setShowPriceModal(true);
                            }}
                            className="p-1.5 border border-amber-200 bg-amber-50 hover:bg-amber-100 text-amber-600 rounded-lg transition-colors"
                            title="Quick Adjust Prices"
                          >
                            <Tag size={12} />
                          </button>
                          <button
                            onClick={() => handleOpenEditModal(p)}
                            className="p-1.5 border border-slate-200 hover:bg-slate-50 text-slate-500 hover:text-slate-800 rounded-lg transition-colors"
                            title="Edit Commodity Properties"
                          >
                            <Edit2 size={12} />
                          </button>
                          {isTopManager && (
                            <button
                              onClick={() => handleDeleteProduct(p)}
                              className="p-1.5 border border-rose-200 bg-rose-50 hover:bg-rose-100 text-rose-600 rounded-lg transition-colors"
                              title="Delete Commodity Permanently"
                            >
                              <Trash2 size={12} />
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}

                {filteredProducts.length === 0 && (
                  <tr>
                    <td colSpan={7} className="py-10 text-center text-slate-400 font-display text-sm">
                      No commodities cataloged
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div className="bg-white rounded-2xl border border-slate-100 shadow-sm overflow-hidden p-6 space-y-4">
          <h3 className="font-display font-semibold text-slate-800 text-sm mb-2">Inventory Ledger Flows</h3>
          <div className="overflow-x-auto border border-slate-100 rounded-xl">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-slate-50 text-slate-400 font-display font-bold text-[10px] tracking-wider uppercase border-b border-slate-100">
                  <th className="py-4.5 px-5">Date & Time</th>
                  <th className="py-4.5 px-5">Commodity</th>
                  <th className="py-4.5 px-5 text-center">Flow Volume</th>
                  <th className="py-4.5 px-5 text-right">Unit Buying Cost</th>
                  <th className="py-4.5 px-5">Operator</th>
                  <th className="py-4.5 px-5">Flow Reason</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 text-slate-700 text-xs font-medium">
                {transactions.map(t => {
                  const isIn = t.type === 'in';
                  return (
                    <tr key={t.id} className="hover:bg-slate-50/50 transition-colors">
                      <td className="py-4 px-5 font-mono text-[10px] text-slate-400">
                        {new Date(t.timestamp).toLocaleString()}
                      </td>
                      <td className="py-4 px-5 font-display font-semibold text-slate-800">
                        {t.productName}
                      </td>
                      <td className="py-4 px-5 text-center">
                        <span className={`font-mono font-bold px-2.5 py-1 rounded-lg text-[10px] flex items-center justify-center gap-1 mx-auto w-24 ${
                          isIn 
                            ? 'bg-emerald-50 text-emerald-700 border border-emerald-100' 
                            : 'bg-rose-50 text-rose-700 border border-rose-100'
                        }`}>
                          {isIn ? <ArrowUpRight size={12} /> : <ArrowDownRight size={12} />}
                          {isIn ? `+${t.quantity}` : `${t.quantity}`}
                        </span>
                      </td>
                      <td className="py-4 px-5 text-right font-mono text-slate-500">
                        shs {t.buyingPriceAtTransaction.toLocaleString()}
                      </td>
                      <td className="py-4 px-5 text-slate-600">
                        {t.operatorName} ({t.operatorId})
                      </td>
                      <td className="py-4 px-5">
                        <span className="capitalize text-[10px] text-slate-400 bg-slate-50 border border-slate-200/50 px-2 py-0.5 rounded-md">
                          {t.reason.replace('_', ' ')}
                        </span>
                      </td>
                    </tr>
                  );
                })}

                {transactions.length === 0 && (
                  <tr>
                    <td colSpan={6} className="py-10 text-center text-slate-400 font-display text-sm">
                      No stock replenishment logs mapped
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* CREATE / EDIT COMMODITY MODAL */}
      <AnimatePresence>
        {showProductModal && (
          <div className="fixed inset-0 bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
            <motion.div
              initial={{ scale: 0.95, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.95, opacity: 0 }}
              className="bg-white rounded-2xl shadow-2xl max-w-lg w-full overflow-hidden border border-slate-100 flex flex-col"
            >
              <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                <h3 className="font-display font-bold text-slate-900 text-sm">
                  {editingProduct ? 'Edit Commodity Properties' : 'Register New Commodity'}
                </h3>
              </div>

              <form onSubmit={handleSaveProduct} className="p-6 space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  {/* Name */}
                  <div className="col-span-2">
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Commodity Name *
                    </label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. Premium White Sugars 2kg"
                      value={formData.name}
                      onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 font-medium"
                    />
                  </div>

                  {/* SKU */}
                  <div>
                    <div className="flex justify-between items-center mb-1">
                      <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider">
                        SKU Code (Barcode)
                      </label>
                      <button
                        type="button"
                        onClick={triggerAutoSKU}
                        className="text-[10px] text-indigo-600 hover:text-indigo-700 font-bold font-sans flex items-center gap-1 transition-colors"
                        title="Auto-generate SKU Code"
                      >
                        <Sparkles size={10} /> Auto-Gen
                      </button>
                    </div>
                    <input
                      type="text"
                      placeholder="Auto-generates if empty"
                      value={formData.sku}
                      onChange={(e) => setFormData({ ...formData, sku: e.target.value })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                  </div>

                  {/* Category */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Category *
                    </label>
                    <select
                      value={formData.category}
                      onChange={(e) => setFormData({ ...formData, category: e.target.value })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    >
                      {dbCategories.map(cat => (
                        <option key={cat} value={cat}>{cat}</option>
                      ))}
                    </select>
                  </div>

                  {/* Buying Price */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Staked buying Cost (shs) *
                    </label>
                    <input
                      type="number"
                      required
                      min={0}
                      placeholder="Cost to buy unit"
                      value={formData.buyingPrice}
                      onChange={(e) => setFormData({ ...formData, buyingPrice: Number(e.target.value) })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                  </div>

                  {/* Limit Price (POS floor) */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Limit price (shs) *
                    </label>
                    <input
                      type="number"
                      required
                      min={0}
                      placeholder="Minimum a worker may sell at"
                      value={formData.wholesalePrice}
                      onChange={(e) => setFormData({ ...formData, wholesalePrice: Number(e.target.value) })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                    <p className="text-[9px] text-slate-400 mt-1">POS checkout floor — sales can't go below this.</p>
                  </div>

                  {/* Selling Price */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Retail sale price (shs) *
                    </label>
                    <input
                      type="number"
                      required
                      min={0}
                      placeholder="Sale to customers price"
                      value={formData.sellingPrice}
                      onChange={(e) => setFormData({ ...formData, sellingPrice: Number(e.target.value) })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                  </div>

                  {/* Current Stock */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Initial stock count *
                    </label>
                    <input
                      type="number"
                      required
                      min={0}
                      placeholder="Available Units count"
                      value={formData.currentStock}
                      onChange={(e) => setFormData({ ...formData, currentStock: Number(e.target.value) })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                  </div>

                  {/* Min Stock Level */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Low stock threshold limit *
                    </label>
                    <input
                      type="number"
                      required
                      min={0}
                      placeholder="Alert limit"
                      value={formData.minStockLevel}
                      onChange={(e) => setFormData({ ...formData, minStockLevel: Number(e.target.value) })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                  </div>

                  {/* Expiration Date */}
                  <div className="col-span-2">
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Expiration Limit Date
                    </label>
                    <input
                      type="date"
                      value={formData.expirationDate}
                      onChange={(e) => setFormData({ ...formData, expirationDate: e.target.value })}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                  </div>
                </div>

                <div className="flex gap-3 pt-3">
                  <button
                    type="submit"
                    className="flex-1 bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-md flex items-center justify-center gap-1.5"
                  >
                    <Save size={13} />
                    {editingProduct ? 'Save Changes' : 'Register Commodity'}
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowProductModal(false)}
                    className="px-4 bg-white hover:bg-slate-50 border border-slate-200 text-slate-600 rounded-xl py-2.5 font-display font-medium text-xs transition-all"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* REPLENISH RESTOCK QUANTITY MODAL */}
      <AnimatePresence>
        {showRestockModal && restockProduct && (
          <div className="fixed inset-0 bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
            <motion.div
              initial={{ scale: 0.95, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.95, opacity: 0 }}
              className="bg-white rounded-2xl shadow-2xl max-w-sm w-full overflow-hidden border border-slate-100 flex flex-col p-6 space-y-4"
            >
              <div className="flex items-center gap-3">
                <div className="p-2.5 bg-indigo-50 text-indigo-600 rounded-xl">
                  <Package size={18} />
                </div>
                <div>
                  <h3 className="font-display font-bold text-slate-900 text-sm">Replenish Inventory</h3>
                  <p className="text-xs text-slate-400 truncate max-w-[200px]">{restockProduct.name}</p>
                </div>
              </div>

              <form onSubmit={handleSaveRestock} className="space-y-4">
                {/* Restock Volume */}
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Replenishment units count *
                  </label>
                  <input
                    type="number"
                    required
                    min={1}
                    placeholder="Volume to add"
                    value={restockQty}
                    onChange={(e) => setRestockQty(e.target.value === '' ? '' : Number(e.target.value))}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                </div>

                {/* Optional Buy price change */}
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Staked Unit buying cost (shs)
                  </label>
                  <input
                    type="number"
                    placeholder={`shs ${restockProduct.buyingPrice}`}
                    value={restockBuyingPrice}
                    onChange={(e) => setRestockBuyingPrice(e.target.value === '' ? '' : Number(e.target.value))}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                  <p className="text-[10px] text-slate-400 mt-1 font-sans">
                    Adjust only if wholesale capital stakes fluctuated
                  </p>
                </div>

                {/* Expiration date picker */}
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Expiration Date
                  </label>
                  <input
                    type="date"
                    value={restockExpirationDate}
                    onChange={(e) => setRestockExpirationDate(e.target.value)}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                  <p className="text-[10px] text-slate-400 mt-1 font-sans">
                    Current Expiry on file: <span className="font-semibold text-slate-600">{restockProduct.expirationDate || 'None'}</span>
                  </p>
                </div>

                {/* Conditional separate batch toggle */}
                {restockExpirationDate && restockExpirationDate !== restockProduct.expirationDate && (
                  <motion.div 
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: 'auto' }}
                    className="p-3 bg-amber-50 border border-amber-200/50 rounded-xl space-y-2"
                  >
                    <label className="flex items-start gap-2 cursor-pointer select-none">
                      <input
                        type="checkbox"
                        checked={createNewBatch}
                        onChange={(e) => setCreateNewBatch(e.target.checked)}
                        className="mt-0.5 h-3.5 w-3.5 text-indigo-600 rounded border-slate-300 focus:ring-indigo-500"
                      />
                      <div className="text-left">
                        <span className="text-[11px] font-display font-bold text-amber-900 block leading-tight">
                          Split into a new separate batch?
                        </span>
                        <span className="text-[10px] text-amber-700 block leading-normal mt-0.5">
                          Since the expiry date differs, checking this generates a separate commodity entry (e.g., "{restockProduct.name} (Batch 2)") to track both expirations separately!
                        </span>
                      </div>
                    </label>
                  </motion.div>
                )}

                <div className="flex gap-3 pt-2">
                  <button
                    type="submit"
                    className="flex-1 bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-md flex items-center justify-center gap-1.5"
                  >
                    <CheckCircle2 size={13} />
                    Confirm Restock
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowRestockModal(false)}
                    className="px-4 bg-white hover:bg-slate-50 border border-slate-200 text-slate-600 rounded-xl py-2.5 font-display font-medium text-xs transition-all"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* BARCODE STICKER LABEL PRINTER MODAL */}
      <AnimatePresence>
        {showBarcodeModal && barcodeProduct && (
          <div className="fixed inset-0 bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
            <motion.div
              initial={{ scale: 0.95, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.95, opacity: 0 }}
              className="bg-white rounded-2xl shadow-2xl max-w-2xl w-full overflow-hidden border border-slate-100 flex flex-col"
            >
              <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                <div className="flex items-center gap-2 text-slate-800">
                  <Printer size={18} className="text-emerald-600" />
                  <h3 className="font-display font-bold text-sm">
                    Barcode Label Sticker Printer
                  </h3>
                </div>
                <span className="bg-emerald-50 text-emerald-700 text-[10px] font-display font-semibold px-2.5 py-1 rounded-lg uppercase">
                  Ready
                </span>
              </div>

              {stickerPrintStatus && (
                <div className={`px-6 py-3 border-b text-xs font-semibold font-display flex items-center gap-2 ${
                  stickerPrintStatus.type === 'success'
                    ? 'bg-emerald-50 border-emerald-100 text-emerald-800'
                    : 'bg-rose-50 border-rose-100 text-rose-800'
                }`}>
                  <span className={`h-1.5 w-1.5 rounded-full animate-ping ${
                    stickerPrintStatus.type === 'success' ? 'bg-emerald-500' : 'bg-rose-500'
                  }`}></span>
                  {stickerPrintStatus.message}
                </div>
              )}

              <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Left side: Controls */}
                <div className="space-y-4">
                  <div>
                    <h4 className="font-display font-bold text-xs text-slate-800 mb-1">Commodity Selected</h4>
                    <p className="text-xs font-medium text-slate-600 truncate bg-slate-50 p-2 rounded-lg border border-slate-100 font-sans">
                      {barcodeProduct.name}
                    </p>
                    <p className="text-[10px] text-slate-400 font-mono mt-1">SKU: {barcodeProduct.sku}</p>
                  </div>

                  {/* Quantity of stickers */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1.5">
                      Number of stickers to print *
                    </label>
                    <input
                      type="number"
                      required
                      min={1}
                      max={200}
                      value={stickerCount}
                      onChange={(e) => setStickerCount(Math.min(200, Math.max(1, Number(e.target.value))))}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                    {/* Preset Buttons */}
                    <div className="flex gap-1.5 mt-2">
                      {[4, 12, 24, 48, 100].map(cnt => (
                        <button
                          key={cnt}
                          type="button"
                          onClick={() => setStickerCount(cnt)}
                          className={`px-2 py-1 rounded-lg text-[10px] font-mono border transition-all ${
                            stickerCount === cnt 
                              ? 'bg-slate-900 border-slate-900 text-white font-bold'
                              : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'
                          }`}
                        >
                          {cnt} pcs
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Custom Price representation on sticker */}
                  <div>
                    <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                      Label Selling Price (shs)
                    </label>
                    <input
                      type="number"
                      placeholder={`shs ${barcodeProduct.sellingPrice}`}
                      value={customStickerPrice}
                      onChange={(e) => setCustomStickerPrice(e.target.value === '' ? '' : Number(e.target.value))}
                      className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                    />
                    <p className="text-[10px] text-slate-400 mt-1">
                      Optionally overrides the selling price on the sticker label
                    </p>
                  </div>

                  {/* Toggles */}
                  <div className="space-y-2.5 pt-1">
                    <label className="flex items-center gap-2.5 cursor-pointer select-none">
                      <input
                        type="checkbox"
                        checked={showBranding}
                        onChange={(e) => setShowBranding(e.target.checked)}
                        className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500/20 h-4 w-4"
                      />
                      <span className="text-xs font-sans text-slate-600 font-medium">Include APEX Branding Header</span>
                    </label>

                    {barcodeProduct.expirationDate && (
                      <label className="flex items-center gap-2.5 cursor-pointer select-none">
                        <input
                          type="checkbox"
                          checked={showExpiryOnSticker}
                          onChange={(e) => setShowExpiryOnSticker(e.target.checked)}
                          className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500/20 h-4 w-4"
                        />
                        <span className="text-xs font-sans text-slate-600 font-medium">Show Expiration Date limit</span>
                      </label>
                    )}
                  </div>
                </div>

                {/* Right side: Live sticker layout preview */}
                <div className="flex flex-col items-center justify-center bg-slate-50 border border-slate-100 rounded-2xl p-6 relative">
                  <span className="absolute top-3 left-3 text-[9px] font-display font-semibold uppercase text-slate-400 tracking-wider">
                    Live Sticker Preview (50mm x 30mm)
                  </span>

                  <div className="w-[200px] h-[120px] bg-white border-2 border-slate-800 rounded-lg p-3 shadow-md flex flex-col justify-between font-sans text-black select-none">
                    {/* Brand header */}
                    {showBranding && (
                      <div className="text-center font-black uppercase tracking-wider text-[9px] leading-none border-b border-dashed border-slate-300 pb-1 text-slate-900">
                        APEX SUPERMARKET
                      </div>
                    )}

                    {/* Commodity info */}
                    <div className="mt-1 flex flex-col">
                      <span className="font-extrabold text-[10px] uppercase tracking-tight truncate leading-tight text-slate-900">
                        {barcodeProduct.name}
                      </span>
                      <span className="text-[7.5px] text-slate-500 font-semibold font-mono uppercase tracking-tight">
                        CAT: {barcodeProduct.category}
                      </span>
                    </div>

                    {/* SVG barcode */}
                    <div className="my-1 flex flex-col items-center justify-center">
                      <div className="w-[150px] h-7 flex items-center justify-center bg-white">
                        <Barcode value={barcodeProduct.sku} height={28} narrowWidth={1.3} />
                      </div>
                      <span className="text-[8px] font-mono tracking-wider font-bold mt-0.5 text-slate-800">
                        {barcodeProduct.sku}
                      </span>
                    </div>

                    {/* Price and Expiry row */}
                    <div className="flex justify-between items-end border-t border-dashed border-slate-300 pt-1 text-slate-900">
                      <div className="flex flex-col text-[7px] text-slate-500 font-medium leading-none">
                        {showExpiryOnSticker && barcodeProduct.expirationDate && (
                          <span>EXP: {barcodeProduct.expirationDate}</span>
                        )}
                        <span>LOC: MAIN STK</span>
                      </div>
                      <div className="text-[11px] font-mono font-black text-right leading-none text-slate-950">
                        shs {(customStickerPrice || barcodeProduct.sellingPrice).toLocaleString()}
                      </div>
                    </div>
                  </div>

                  <p className="text-[10px] text-slate-400 text-center mt-4 max-w-[200px] leading-normal font-sans">
                    Fits any mini roll label printer (such as Xprinter, Phomemo, NIIMBOT, Brother)
                  </p>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="p-4 bg-slate-50 border-t border-slate-100 flex flex-col sm:flex-row gap-3">
                <button
                  type="button"
                  onClick={handlePrintStickers}
                  className="flex-1 bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-sm hover:shadow flex items-center justify-center gap-2"
                >
                  <Printer size={14} />
                  Print Dialog ({stickerCount} copies)
                </button>
                <button
                  type="button"
                  onClick={exportStickersHTML}
                  className="flex-1 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-sm hover:shadow flex items-center justify-center gap-2"
                >
                  <Download size={14} />
                  Export & Print File
                </button>
                <button
                  type="button"
                  onClick={() => setShowBarcodeModal(false)}
                  className="px-5 bg-white hover:bg-slate-100 border border-slate-200 text-slate-700 rounded-xl py-2.5 font-display font-medium text-xs uppercase tracking-wide transition-all"
                >
                  Close
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* HIDDEN IN WEB UI, SHOWN ONLY DURING PRINT VIA CSS MEDIA QUERY */}
      {showBarcodeModal && barcodeProduct && (
        <div id="sticker-print-area" className="hidden print:block">
          <div className="flex flex-wrap gap-4 p-4 justify-start">
            {Array.from({ length: stickerCount }).map((_, i) => (
              <div 
                key={i} 
                className="w-[180px] h-[110px] border border-dashed border-slate-400 p-2.5 rounded-md flex flex-col justify-between bg-white text-black font-sans page-break-inside-avoid relative overflow-hidden"
                style={{ pageBreakInside: 'avoid', breakInside: 'avoid' }}
              >
                {/* Branding */}
                {showBranding && (
                  <div className="text-center font-black uppercase tracking-wider text-[8px] leading-none border-b border-dashed border-slate-300 pb-1">
                    APEX SUPERMARKET
                  </div>
                )}
                
                {/* Product details */}
                <div className="mt-1 flex flex-col">
                  <span className="font-bold text-[9px] uppercase tracking-tight truncate leading-tight">
                    {barcodeProduct.name}
                  </span>
                  <span className="text-[7px] text-slate-500 font-mono">
                    CAT: {barcodeProduct.category}
                  </span>
                </div>

                {/* Barcode representation */}
                <div className="my-1.5 flex flex-col items-center justify-center">
                  <div className="w-[140px] h-6 flex items-center justify-center">
                    <Barcode value={barcodeProduct.sku} height={24} narrowWidth={1.2} />
                  </div>
                  <span className="text-[7px] font-mono tracking-wider mt-0.5 font-bold">
                    {barcodeProduct.sku}
                  </span>
                </div>

                {/* Price and Expiry info */}
                <div className="flex justify-between items-end border-t border-dashed border-slate-300 pt-1">
                  <div className="flex flex-col text-[6px] text-slate-500 leading-none">
                    {showExpiryOnSticker && barcodeProduct.expirationDate && (
                      <span>EXP: {barcodeProduct.expirationDate}</span>
                    )}
                    <span>LOC: MAIN STK</span>
                  </div>
                  <div className="text-[10px] font-mono font-black text-right leading-none">
                    shs {(customStickerPrice || barcodeProduct.sellingPrice).toLocaleString()}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* CATEGORY MANAGER MODAL */}
      <AnimatePresence>
        {showCategoryModal && (
          <div className="fixed inset-0 bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 overflow-y-auto">
            <motion.div
              initial={{ scale: 0.95, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.95, opacity: 0 }}
              className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden border border-slate-100 flex flex-col"
            >
              <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Tag size={16} className="text-slate-500" />
                  <h3 className="font-display font-bold text-slate-900 text-sm">
                    Manage Product Categories
                  </h3>
                </div>
                <button
                  onClick={() => setShowCategoryModal(false)}
                  className="text-slate-400 hover:text-slate-600 text-xs font-semibold uppercase tracking-wider"
                >
                  Close
                </button>
              </div>

              <div className="p-6 space-y-6">
                {/* Create Category form */}
                <form onSubmit={handleAddCategory} className="flex gap-2">
                  <input
                    type="text"
                    required
                    placeholder="e.g. Fresh Produce"
                    value={newCatName}
                    onChange={(e) => setNewCatName(e.target.value)}
                    className="flex-1 bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800 font-medium"
                  />
                  <button
                    type="submit"
                    className="bg-slate-900 hover:bg-slate-800 text-white rounded-xl px-4 py-2 font-display font-bold text-xs uppercase tracking-wide transition-all shadow-sm hover:shadow flex items-center gap-1.5"
                  >
                    <Plus size={12} /> Add
                  </button>
                </form>

                {/* List Categories */}
                <div className="space-y-2 max-h-[250px] overflow-y-auto pr-1">
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-2">
                    Existing Categories ({dbCategories.length})
                  </label>
                  {dbCategories.map(cat => (
                    <div
                      key={cat}
                      className="flex items-center justify-between bg-slate-50 border border-slate-150 p-2.5 rounded-xl text-xs text-slate-700 font-medium"
                    >
                      {editingCatName === cat ? (
                        <div className="flex items-center gap-1.5 flex-1 mr-2">
                          <input
                            type="text"
                            value={editingCatValue}
                            onChange={(e) => setEditingCatValue(e.target.value)}
                            className="flex-1 bg-white border border-slate-200 rounded-lg px-2 py-1 text-xs focus:outline-none text-slate-800 font-medium"
                          />
                          <button
                            type="button"
                            onClick={() => handleSaveEditCategory(cat)}
                            className="bg-emerald-500 hover:bg-emerald-600 text-white p-1.5 rounded-lg transition-colors flex items-center justify-center"
                            title="Save Edit"
                          >
                            <Save size={12} />
                          </button>
                          <button
                            type="button"
                            onClick={() => setEditingCatName(null)}
                            className="bg-slate-200 hover:bg-slate-300 text-slate-600 px-2 py-1 rounded-lg text-[10px] font-semibold"
                          >
                            Cancel
                          </button>
                        </div>
                      ) : (
                        <>
                          <span className="truncate">{cat}</span>
                          <div className="flex items-center gap-1">
                            <button
                              type="button"
                              onClick={() => handleStartEditCategory(cat)}
                              className="p-1 text-slate-400 hover:text-slate-600 hover:bg-slate-200 rounded-md transition-all"
                              title="Edit Name"
                            >
                              <Edit2 size={12} />
                            </button>
                            <button
                              type="button"
                              onClick={() => handleDeleteCategory(cat)}
                              className="p-1 text-red-400 hover:text-red-600 hover:bg-red-50 rounded-md transition-all"
                              title="Delete Category"
                            >
                              <Trash2 size={12} />
                            </button>
                          </div>
                        </>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* QUICK PRICE ADJUSTER MODAL */}
      <AnimatePresence>
        {showPriceModal && priceProduct && (
          <div className="fixed inset-0 bg-slate-950/60 backdrop-blur-sm flex items-center justify-center p-4 z-50">
            <motion.div
              initial={{ scale: 0.95, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.95, opacity: 0 }}
              className="bg-white rounded-2xl shadow-2xl max-w-sm w-full overflow-hidden border border-slate-100 flex flex-col p-6 space-y-4"
            >
              <div className="flex items-center gap-3">
                <div className="p-2.5 bg-amber-50 text-amber-600 rounded-xl">
                  <Tag size={18} />
                </div>
                <div>
                  <h3 className="font-display font-bold text-slate-900 text-sm">Quick Price Adjuster</h3>
                  <p className="text-xs text-slate-400 truncate max-w-[200px]">{priceProduct.name}</p>
                </div>
              </div>

              <form onSubmit={handleSaveQuickPrice} className="space-y-4">
                {/* Buying Price */}
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Wholesale buying cost (shs) *
                  </label>
                  <input
                    type="number"
                    required
                    min={0}
                    value={quickBuyingPrice}
                    onChange={(e) => setQuickBuyingPrice(e.target.value === '' ? '' : Number(e.target.value))}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                </div>

                {/* Selling Price */}
                <div>
                  <label className="block text-[10px] font-display font-semibold text-slate-400 uppercase tracking-wider mb-1">
                    Retail Selling Price (shs) *
                  </label>
                  <input
                    type="number"
                    required
                    min={0}
                    value={quickSellingPrice}
                    onChange={(e) => setQuickSellingPrice(e.target.value === '' ? '' : Number(e.target.value))}
                    className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-xs font-mono focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 text-slate-800"
                  />
                </div>

                <div className="flex gap-3 pt-2">
                  <button
                    type="submit"
                    className="flex-1 bg-slate-900 hover:bg-slate-800 text-white rounded-xl py-2.5 font-display font-semibold text-xs tracking-wide uppercase transition-all shadow-md flex items-center justify-center gap-1.5"
                  >
                    <Save size={13} />
                    Update Prices
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowPriceModal(false)}
                    className="px-4 bg-white hover:bg-slate-50 border border-slate-200 text-slate-600 rounded-xl py-2.5 font-display font-medium text-xs transition-all"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};
export default InventoryView;
