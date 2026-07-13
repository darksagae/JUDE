import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:apex_retail_core/apex_retail_core.dart';

class PosView extends StatefulWidget {
  const PosView({super.key});
  @override
  State<PosView> createState() => _PosViewState();
}

class _CartLine {
  // Not final: re-pointed to the live Product instance on every build (see
  // _PosViewState.build) so a price/stock edit made in Inventory while this
  // item is already sitting in an active cart shows up immediately, instead
  // of only after the line is removed and re-added.
  Product product;
  int quantity;
  num unitPrice;
  late final TextEditingController qtyCtrl;
  late final TextEditingController priceCtrl;

  _CartLine(this.product, this.quantity, this.unitPrice) {
    qtyCtrl = TextEditingController(text: '$quantity');
    priceCtrl = TextEditingController(text: _priceText(unitPrice));
  }

  /// The per-unit minimum a checkout price may not go below.
  /// Expired stock is exempt — it may be sold at any price, even a loss,
  /// since moving it out is better than a total write-off.
  num get floor => isProductExpired(product) ? 0 : product.wholesalePrice;

  static String _priceText(num v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void syncFields() {
    final q = '$quantity';
    if (qtyCtrl.text != q) qtyCtrl.text = q;
    final p = _priceText(unitPrice);
    if (priceCtrl.text != p) priceCtrl.text = p;
  }

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _PosViewState extends State<PosView> {
  final _search = TextEditingController();
  final _scan = TextEditingController();
  final _amountPaid = TextEditingController();
  final _mmTxId = TextEditingController();
  final _customerName = TextEditingController();
  final _customerContact = TextEditingController();
  String _pledgeDate = DateTime.now()
      .add(const Duration(days: 7))
      .toIso8601String()
      .substring(0, 10);
  String _category = 'All';
  final List<_CartLine> _cart = [];
  String _payment = 'cash';
  bool _showAlerts = false;

  @override
  void dispose() {
    _search.dispose();
    _scan.dispose();
    _amountPaid.dispose();
    _mmTxId.dispose();
    _customerName.dispose();
    _customerContact.dispose();
    for (final line in _cart) {
      line.dispose();
    }
    super.dispose();
  }

  void _removeCartLine(_CartLine line) {
    line.dispose();
    _cart.remove(line);
  }

  void _clearCart() {
    for (final line in _cart) {
      line.dispose();
    }
    _cart.clear();
  }

  // Commits whatever price the staff has typed (even if not yet confirmed
  // via Enter/blur) into line.unitPrice, so a subsequent syncFields() call
  // — triggered by a qty change — doesn't clobber it back to the old price.
  void _commitLivePrice(_CartLine line) {
    final parsed = num.tryParse(line.priceCtrl.text.trim());
    if (parsed == null || parsed == line.unitPrice) return;
    final floor = line.floor;
    if (floor > 0 && parsed < floor) return;
    line.unitPrice = parsed;
  }

  void _applyQty(_CartLine line) {
    final parsed = int.tryParse(line.qtyCtrl.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _removeCartLine(line));
      return;
    }
    final max = line.product.currentStock.toInt();
    setState(() {
      _commitLivePrice(line);
      line.quantity = parsed > max ? max : parsed;
      line.syncFields();
    });
  }

  void _applyUnitPrice(_CartLine line) {
    final parsed = num.tryParse(line.priceCtrl.text.trim());
    if (parsed == null) {
      line.syncFields();
      return;
    }
    final floor = line.floor;
    if (floor > 0 && parsed < floor) {
      _toast('Price cannot be below floor of ${shs(floor)}',
          color: AppColors.amber600);
      line.syncFields();
      return;
    }
    setState(() {
      line.unitPrice = parsed;
      line.syncFields();
    });
  }

  void _syncCartFromFields() {
    setState(() {
      for (final line in List<_CartLine>.from(_cart)) {
        final price = num.tryParse(line.priceCtrl.text.trim());
        if (price != null && (line.floor <= 0 || price >= line.floor)) {
          line.unitPrice = price;
        } else {
          line.syncFields();
        }

        final qty = int.tryParse(line.qtyCtrl.text.trim());
        if (qty == null || qty <= 0) {
          _removeCartLine(line);
          continue;
        }
        final max = line.product.currentStock.toInt();
        line.quantity = qty > max ? max : qty;
        line.syncFields();
      }
    });
  }

  void _toast(String msg, {Color color = AppColors.slate900}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _addToCart(Product p) async {
    if (p.currentStock <= 0) return;
    final app = context.read<AppState>();
    if (isProductExpired(p)) {
      if (app.expiredControl == 'restrict') {
        final pass = await _promptPasscode(p);
        if (pass == null) return;
        if (app.supervisorPasscodeMatches(pass)) {
          app.logAction(app.session.userId, app.session.name, app.session.role,
              'EXPIRED_BYPASS',
              'Authorized sale of expired commodity: ${p.name} (SKU: ${p.sku})');
          _toast('Override authorized. Product added to cart.',
              color: AppColors.emerald);
        } else {
          _toast('Authorization failed. Incorrect supervisor passcode.',
              color: AppColors.rose);
          return;
        }
      } else {
        final ok = await _confirmExpired(p);
        if (ok != true) return;
      }
    }
    setState(() {
      final existing =
          _cart.where((c) => c.product.id == p.id).cast<_CartLine?>().firstOrNull;
      if (existing != null) {
        if (existing.quantity < p.currentStock) {
          _commitLivePrice(existing);
          existing.quantity++;
          existing.syncFields();
        }
      } else {
        _cart.add(_CartLine(p, 1, p.retailPrice));
      }
    });
  }

  Future<String?> _promptPasscode(Product p) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Expired Commodity Restricted'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              '"${p.name}" is EXPIRED and restricted by store policy. Enter a Manager or Top Manager passcode to bypass:',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Supervisor passcode')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Authorize')),
        ],
      ),
    );
  }

  Future<bool?> _confirmExpired(Product p) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Expired Warning'),
          content: Text(
              '"${p.name}" is EXPIRED. Add this expired commodity to checkout anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add Anyway')),
          ],
        ),
      );

  void _scanSku(String value, List<Product> products) {
    final sku = value.trim().toUpperCase();
    if (sku.isEmpty) return;
    final found = products
        .where((p) => p.sku.toUpperCase() == sku)
        .cast<Product?>()
        .firstOrNull;
    if (found != null) {
      _addToCart(found);
      _toast('Scan Success: "${found.name}" added to cart!',
          color: AppColors.emerald);
    } else {
      _toast('SKU "$sku" not found in catalog.', color: AppColors.rose);
    }
    _scan.clear();
  }

  // Reads the field text live (even before it's committed via blur/submit)
  // so the running total reflects what staff just typed, not just what was
  // last confirmed. Falls back to the committed value if unparseable.
  num _liveUnitPrice(_CartLine c) =>
      num.tryParse(c.priceCtrl.text.trim()) ?? c.unitPrice;
  num _liveQty(_CartLine c) =>
      num.tryParse(c.qtyCtrl.text.trim()) ?? c.quantity;

  num get _cartTotal => _cart.fold<num>(
      0, (a, c) => a + _liveUnitPrice(c) * _liveQty(c));
  num get _cartBuying =>
      _cart.fold<num>(0, (a, c) => a + c.product.buyingPrice * _liveQty(c));

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    _syncCartFromFields();
    if (_cart.isEmpty) return;
    final app = context.read<AppState>();
    if (_payment == 'mobile_money' && _mmTxId.text.trim().isEmpty) {
      _toast('Mobile Money Transaction ID is required', color: AppColors.amber600);
      return;
    }
    final total = _cartTotal;
    final paidRaw = _amountPaid.text.trim();

    num cashVal;
    num loanAmount = 0;
    if (_payment == 'partial') {
      // Split: whatever the customer pays now in cash, the rest becomes a loan.
      cashVal = num.tryParse(paidRaw) ?? 0;
      if (cashVal >= total) {
        // Nothing left to loan — treat as a normal fully-paid sale.
        loanAmount = 0;
      } else {
        loanAmount = total - cashVal;
        if (_customerName.text.trim().isEmpty) {
          _toast('Customer name is required for the loan balance',
              color: AppColors.amber600);
          return;
        }
      }
    } else {
      cashVal = _payment == 'cash' ? (num.tryParse(paidRaw) ?? total) : total;
      if (cashVal < total) {
        _toast('Insufficient payment amount', color: AppColors.amber600);
        return;
      }
    }

    final items = _cart
        .map((c) => SaleItem(
              id: genId(),
              productId: c.product.id,
              productName: c.product.name,
              quantity: c.quantity,
              buyingPrice: c.product.buyingPrice,
              sellingPrice: c.unitPrice,
              totalBuyingPrice: c.product.buyingPrice * c.quantity,
              totalSellingPrice: c.unitPrice * c.quantity,
              profit: (c.unitPrice - c.product.buyingPrice) * c.quantity,
            ))
        .toList();

    // Cash portion actually collected (capped at total for change display).
    final settled = loanAmount > 0 ? cashVal : (cashVal > total ? total : cashVal);

    final sale = app.addSale(
      items: items,
      totalAmount: total,
      totalBuyingPrice: _cartBuying,
      totalProfit: total - _cartBuying,
      paymentMethod: _payment,
      amountPaid: settled,
      changeDue: (loanAmount > 0 || _payment != 'cash') ? 0 : (cashVal - total),
      loanAmount: loanAmount,
      customerName:
          _customerName.text.trim().isEmpty ? null : _customerName.text.trim(),
      customerContact: _customerContact.text.trim().isEmpty
          ? null
          : _customerContact.text.trim(),
      loanPledgeDate: _pledgeDate,
      mobileMoneyTxId:
          _payment == 'mobile_money' ? _mmTxId.text.trim().toUpperCase() : null,
    );

    // Clear indicator of the outcome.
    if (loanAmount > 0) {
      _toast(
          'Sale saved. shs ${money(settled)} paid, shs ${money(loanAmount)} on loan for ${sale.customerName}.',
          color: AppColors.amber600);
    } else {
      _toast('Sale complete — PAID IN FULL (0 balance).',
          color: AppColors.emerald);
    }

    setState(() {
      _clearCart();
      _amountPaid.clear();
      _mmTxId.clear();
      _customerName.clear();
      _customerContact.clear();
    });

    if (mounted) {
      await ReceiptDialog.show(context, sale, app.printerSettings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final products = app.products;
    // Re-point every cart line at the live Product instance so an Inventory
    // price/stock edit shows up immediately, even for items already in the
    // active cart — not just newly-added ones.
    final byId = {for (final p in products) p.id: p};
    for (final line in _cart) {
      final live = byId[line.product.id];
      if (live != null) line.product = live;
    }
    final cats = <String>['All', ...{for (final p in products) p.category}];
    final query = _search.text.toLowerCase();
    final filtered = products.where((p) {
      final matchS = p.name.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query);
      final matchC = _category == 'All' || p.category == _category;
      return matchS && matchC;
    }).toList()
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    final lowStock =
        products.where((p) => p.currentStock <= p.minStockLevel).toList();
    final expired = products.where(isProductExpired).toList();
    final nearExpiry = products.where((p) => isProductNearExpiry(p)).toList();

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 600;
      final catalog = RepaintBoundary(
          child: _catalog(
              filtered, cats, lowStock, expired, nearExpiry, products, app));
      final cart = RepaintBoundary(child: _cartPanel());
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: catalog),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: cart),
          ],
        );
      }
      return Column(children: [catalog, const SizedBox(height: 20), cart]);
    });
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slate100),
        ),
        child: child,
      );

  Widget _catalog(List<Product> filtered, List<String> cats,
      List<Product> lowStock, List<Product> expired, List<Product> nearExpiry,
      List<Product> products, AppState app) {
    final warnings = lowStock.length + expired.length + nearExpiry.length;
    final outOfStock = lowStock.where((p) => p.currentStock <= 0).toList();
    final justLow = lowStock.where((p) => p.currentStock > 0).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (warnings > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                border: Border.all(color: const Color(0xFFFECDD3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.rose),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Store Alert Monitor: $warnings Warnings Active',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF9F1239))),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showAlerts = !_showAlerts),
                    child: Text(_showAlerts ? 'Hide' : 'View',
                        style: const TextStyle(fontSize: 10)),
                  ),
                ]),
                if (_showAlerts)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Column(children: [
                        for (final p in expired)
                          _alertRow('❌ [EXPIRED] ${p.name}',
                              'Exp: ${p.expirationDate}', const Color(0xFF9F1239)),
                        for (final p in outOfStock)
                          _alertRow('🚫 [OUT OF STOCK] ${p.name}', '0 left',
                              AppColors.red),
                        for (final p in nearExpiry)
                          _alertRow('⚠️ [NEAR EXPIRY] ${p.name}',
                              'Exp: ${p.expirationDate}', AppColors.red),
                        for (final p in justLow)
                          _alertRow('📉 [REPLENISH] ${p.name}',
                              '${p.currentStock} left', AppColors.amber600),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          // Scanner emulation input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              border: Border.all(color: AppColors.slate200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.qr_code_scanner,
                  size: 16, color: AppColors.emerald),
              const SizedBox(width: 8),
              const Text('Scanner: ',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
              Expanded(
                child: TextField(
                  controller: _scan,
                  decoration: const InputDecoration(
                      hintText: 'Type SKU & press Enter to scan',
                      isDense: true),
                  onSubmitted: (v) => _scanSku(v, products),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search commodity by name or SKU...',
            ),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tap ★ on a product to pin it to the top for quick checkout.',
              style: TextStyle(fontSize: 10, color: AppColors.slate400),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = cats[i];
                final active = _category == cat;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? AppColors.slate900 : AppColors.slate50,
                      border: Border.all(color: AppColors.slate200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(cat,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.white : AppColors.slate600)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: Text('No matching commodities found',
                      style: TextStyle(color: AppColors.slate400))),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent:
                    MediaQuery.sizeOf(context).width < 400 ? 160 : 230,
                mainAxisExtent: 168,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _productCard(filtered[i], app),
            ),
        ],
      ),
    );
  }

  Widget _alertRow(String a, String b, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(a,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: color))),
          Text(b, style: TextStyle(fontSize: 9, color: color)),
        ]),
      );

  Widget _productCard(Product p, AppState app) {
    final inCart =
        _cart.where((c) => c.product.id == p.id).cast<_CartLine?>().firstOrNull;
    final remaining = (p.currentStock - (inCart?.quantity ?? 0)).toInt();
    final expired = isProductExpired(p);
    final nearExpiry = isProductNearExpiry(p);
    final out = remaining <= 0;
    final fav = p.isFavorite;
    return RepaintBoundary(
      child: InkWell(
      onTap: out ? null : () => _addToCart(p),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (expired || out)
              ? const Color(0xFFFFF1F2)
              : nearExpiry
                  ? const Color(0xFFFEF2F2)
                  : fav
                      ? const Color(0xFFFFFBEB)
                      : Colors.white,
          border: Border.all(
              color: fav
                  ? AppColors.amber.withValues(alpha: 0.5)
                  : (expired || out)
                      ? const Color(0xFFFECDD3)
                      : nearExpiry
                          ? AppColors.red.withValues(alpha: 0.35)
                          : AppColors.slate200,
              width: fav ? 1.5 : (expired || out || nearExpiry) ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(p.sku,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.slate400)),
              ),
              GestureDetector(
                onTap: () => app.toggleProductFavorite(p.id),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    fav ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 20,
                    color: fav ? AppColors.amber600 : AppColors.slate400,
                  ),
                ),
              ),
              if (expired) ...[
                const SizedBox(width: 4),
                _tag('Expired', AppColors.red, Colors.white)
              ] else if (out) ...[
                const SizedBox(width: 4),
                _tag('Out of Stock', AppColors.red, Colors.white),
              ] else if (nearExpiry) ...[
                const SizedBox(width: 4),
                _tag('Expiring', AppColors.red, Colors.white),
              ],
            ]),
            const SizedBox(height: 6),
            Text(p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate800)),
            Text(p.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.slate400)),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('From',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.slate400)),
                      Text('${shs(p.retailPrice)}/${p.unitLabel}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.slate900)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Remaining',
                        style:
                            TextStyle(fontSize: 9, color: AppColors.slate400)),
                    Text(out ? 'OUT' : '$remaining left',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: out
                                ? AppColors.red
                                : remaining <= p.minStockLevel
                                    ? AppColors.amber
                                    : AppColors.emerald)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }

  Widget _tag(String s, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(s,
            style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.bold, color: fg)),
      );

  Widget _cartPanel() {
    final total = _cartTotal;
    final paid = num.tryParse(_amountPaid.text.trim()) ?? 0;
    final change = (paid - total).clamp(0, double.infinity);
    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.shopping_cart_outlined,
                      size: 18, color: AppColors.indigo),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active Checkout',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate800)),
                    Text(
                        '${_cart.fold<int>(0, (a, c) => a + c.quantity)} items',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.slate400)),
                  ],
                ),
                const Spacer(),
                if (_cart.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_clearCart),
                    child: const Text('Clear',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.slate400)),
                  ),
              ]),
            ),
          ),
          const Divider(height: 1, color: AppColors.slate100),
          if (_cart.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 32, color: AppColors.slate200),
                  SizedBox(height: 8),
                  Text('Basket is empty',
                      style: TextStyle(color: AppColors.slate400, fontSize: 12)),
                ]),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _cart.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 16, color: AppColors.slate100),
                itemBuilder: (_, i) => _cartLine(_cart[i]),
              ),
            ),
          if (_cart.isNotEmpty) _checkoutForm(total, change.toDouble()),
        ],
      ),
    );
  }

  Widget _cartLine(_CartLine line) {
    return RepaintBoundary(
        child: LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 360;
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: narrow ? 64 : 76,
            child: TextField(
              controller: line.priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [NoLeadingZeroFormatter()],
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.indigo),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                hintText: 'Price',
                filled: true,
                fillColor: const Color(0xFFEEF2FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                      color: AppColors.indigo.withValues(alpha: 0.35)),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyUnitPrice(line),
              onEditingComplete: () => _applyUnitPrice(line),
            ),
          ),
          const SizedBox(width: 4),
          _qtyBtn(Icons.remove, () {
            setState(() {
              if (line.quantity <= 1) {
                _removeCartLine(line);
              } else {
                _commitLivePrice(line);
                line.quantity--;
                line.syncFields();
              }
            });
          }),
          SizedBox(
            width: 44,
            child: TextField(
              controller: line.qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [NoLeadingZeroFormatter()],
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.slate200),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyQty(line),
              onEditingComplete: () => _applyQty(line),
            ),
          ),
          _qtyBtn(Icons.add, () {
            if (line.quantity < line.product.currentStock) {
              setState(() {
                _commitLivePrice(line);
                line.quantity++;
                line.syncFields();
              });
            }
          }),
        ],
      );
      final customPrice = _liveUnitPrice(line) != line.product.retailPrice;
      final floorLabel = Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
            isProductExpired(line.product)
                ? 'No limit (expired stock)'
                : 'Limit: ${shs(line.floor)}/${line.product.unitLabel}',
            style: const TextStyle(fontSize: 9, color: AppColors.slate400)),
        if (customPrice) ...[
          const SizedBox(width: 4),
          const Text('• custom price applied',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.emerald)),
        ],
      ]);

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    floorLabel,
                  ],
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: AppColors.slate400),
                onPressed: () => setState(() => _removeCartLine(line)),
              ),
            ]),
            const SizedBox(height: 8),
            controls,
          ],
        );
      }

      return Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              floorLabel,
            ],
          ),
        ),
        controls,
        IconButton(
          icon: const Icon(Icons.delete_outline,
              size: 16, color: AppColors.slate400),
          onPressed: () => setState(() => _removeCartLine(line)),
        ),
      ]);
    }));
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.slate200)),
          child: Icon(icon, size: 12, color: AppColors.slate600),
        ),
      );

  Widget _checkoutForm(num total, double change) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.slate50,
        border: Border(top: BorderSide(color: AppColors.slate100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Due:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(shs(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 340;
            final buttons = [
              _payBtn('cash', narrow ? 'Cash' : '💵 Cash'),
              _payBtn('mobile_money', narrow ? 'Mobile' : '📱 Mobile'),
              _payBtn('partial', narrow ? 'Loan' : '🤝 Cash+Loan'),
            ];
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    buttons[i],
                  ],
                ],
              );
            }
            return Row(children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: 6),
              Expanded(child: buttons[1]),
              const SizedBox(width: 6),
              Expanded(child: buttons[2]),
            ]);
          }),
          const SizedBox(height: 12),
          if (_payment == 'cash')
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CASH RECEIVED',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slate400)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _amountPaid,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [NoLeadingZeroFormatter()],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(hintText: 'shs $total'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CHANGE DUE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slate400)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.slate200),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(shs(change),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.emerald)),
                    ),
                  ],
                ),
              ),
            ]),
          if (_payment == 'mobile_money')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MOBILE MONEY TRANSACTION ID',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate400)),
                const SizedBox(height: 4),
                TextField(
                  controller: _mmTxId,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      hintText: 'e.g. PP2607031122, MTN-8910...'),
                ),
              ],
            ),
          if (_payment == 'partial') _partialSection(total),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.indigo,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _checkout,
            icon: const Icon(Icons.credit_card, size: 16),
            label: const Text('COMPLETE POS & PRINT',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _partialSection(num total) {
    final cash = num.tryParse(_amountPaid.text.trim()) ?? 0;
    final loan = (total - cash).clamp(0, double.infinity);
    final fullyPaid = loan <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CASH PAID NOW',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.slate400)),
        const SizedBox(height: 4),
        TextField(
          controller: _amountPaid,
          keyboardType: TextInputType.number,
          inputFormatters: const [NoLeadingZeroFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: 'shs 0  (of $total)'),
        ),
        const SizedBox(height: 8),
        // Live outcome indicator.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: fullyPaid
                ? AppColors.emerald.withValues(alpha: 0.1)
                : AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            fullyPaid
                ? '✅ PAID IN FULL — 0 balance'
                : '🤝 Loan balance: shs ${money(loan)}  (remains as credit)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: fullyPaid ? AppColors.emerald : AppColors.amber600),
          ),
        ),
        if (!fullyPaid) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _customerName,
                decoration: const InputDecoration(
                    labelText: 'Customer name *', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _customerContact,
                decoration: const InputDecoration(
                    labelText: 'Contact', isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_pledgeDate) ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime(2032),
              );
              if (picked != null) {
                setState(() =>
                    _pledgeDate = picked.toIso8601String().substring(0, 10));
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Pledged repayment date',
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today, size: 16)),
              child: Text(_pledgeDate),
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _payBtn(String method, String label) {
    final active = _payment == method;
    return GestureDetector(
      onTap: () => setState(() => _payment = method),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.slate900 : Colors.white,
          border: Border.all(
              color: active ? AppColors.slate900 : AppColors.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                color: active ? Colors.white : AppColors.slate600)),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
