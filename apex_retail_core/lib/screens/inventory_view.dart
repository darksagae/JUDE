import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:provider/provider.dart';

import 'package:apex_retail_core/branding.dart';
import 'package:apex_retail_core/data/app_state.dart';
import 'package:apex_retail_core/models/models.dart';
import 'package:apex_retail_core/theme.dart';
import 'package:apex_retail_core/utils/format.dart';
import 'package:apex_retail_core/utils/input_formatters.dart';
import 'package:apex_retail_core/utils/responsive.dart';
import 'package:apex_retail_core/utils/print_service.dart';

class InventoryView extends StatefulWidget {
  const InventoryView({super.key});
  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  String _tab = 'catalog';
  final _search = TextEditingController();
  String _category = 'All';
  final _catalogScroll = ScrollController();
  final _ledgerScroll = ScrollController();

  @override
  void dispose() {
    _search.dispose();
    _catalogScroll.dispose();
    _ledgerScroll.dispose();
    super.dispose();
  }

  void _banner(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: err ? AppColors.rose : AppColors.emerald,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerBar(),
        const SizedBox(height: 16),
        if (_tab == 'catalog') _catalog(app) else _ledger(app),
      ],
    );
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

  Widget _headerBar() {
    return _card(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _tabBtn('catalog', 'Commodity Catalog'),
              _tabBtn('ledger', 'Replenishment Ledger'),
            ]),
          ),
          if (_tab == 'catalog')
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _openCategoryManager,
                icon: const Icon(Icons.sell_outlined, size: 14),
                label: const Text('Manage Categories'),
              ),
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.slate900),
                onPressed: () => _openProductModal(null),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Commodity'),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _tabBtn(String id, String label) {
    final active = _tab == id;
    return GestureDetector(
      onTap: () => setState(() => _tab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3)]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.slate900 : AppColors.slate500)),
      ),
    );
  }

  Widget _catalog(AppState app) {
    final cats = <String>['All', ...app.categories];
    final query = _search.text.toLowerCase();
    final filtered = app.products.where((p) {
      final matchS = p.name.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query);
      final matchC = _category == 'All' || p.category == _category;
      return matchS && matchC;
    }).toList();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search catalog by name, SKU, or category...',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.slate900 : Colors.white,
                      border: Border.all(color: AppColors.slate200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(cat,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color:
                                active ? Colors.white : AppColors.slate600)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Scrollbar(
            controller: _catalogScroll,
            thumbVisibility: true,
            trackVisibility: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                controller: _catalogScroll,
                scrollDirection: Axis.horizontal,
                child: DataTable(
              columnSpacing: 20,
              headingRowHeight: 40,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(label: Text('SKU / Name')),
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Buying'), numeric: true),
                DataColumn(label: Text('Limit Price'), numeric: true),
                DataColumn(label: Text('Selling Price'), numeric: true),
                DataColumn(label: Text('Stock')),
                DataColumn(label: Text('Expiry')),
                DataColumn(label: Text('Actions')),
              ],
              rows: filtered.map((p) => _productRow(app, p)).toList(),
                ),
              ),
            ),
          ),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                  child: Text('No commodities cataloged',
                      style: TextStyle(color: AppColors.slate400))),
            ),
        ],
      ),
    );
  }

  DataRow _productRow(AppState app, Product p) {
    final isLow = p.currentStock <= p.minStockLevel;
    final expired = isProductExpired(p);
    return DataRow(cells: [
      DataCell(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(p.sku,
              style: const TextStyle(fontSize: 9, color: AppColors.slate400)),
          Text(p.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      )),
      DataCell(Text(p.category, style: const TextStyle(fontSize: 11))),
      DataCell(Text(shs(p.buyingPrice),
          style: const TextStyle(color: AppColors.slate500))),
      DataCell(Text(shs(p.wholesalePrice),
          style: const TextStyle(fontWeight: FontWeight.w600))),
      DataCell(Text('${shs(p.retailPrice)}/${p.unitLabel}',
          style: const TextStyle(fontWeight: FontWeight.w600))),
      DataCell(Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.currentStock} ${p.unitLabel}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: p.currentStock <= 0
                      ? AppColors.red
                      : isLow
                          ? AppColors.amber
                          : AppColors.emerald)),
          if (isLow)
            const Text('low stock',
                style: TextStyle(fontSize: 9, color: AppColors.amber)),
        ],
      )),
      DataCell(p.expirationDate != null
          ? Text(p.expirationDate!,
              style: TextStyle(
                  fontSize: 11,
                  color: expired ? AppColors.red : AppColors.slate500))
          : const Text('No Expiry', style: TextStyle(color: AppColors.slate400))),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton.icon(
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              backgroundColor: const Color(0xFFEEF2FF),
              foregroundColor: AppColors.indigo),
          onPressed: () => _openRestockModal(app, p),
          icon: const Icon(Icons.inventory_2_outlined, size: 12),
          label: const Text('Restock', style: TextStyle(fontSize: 10)),
        ),
        IconButton(
          tooltip: 'Print barcode stickers',
          icon: const Icon(Icons.print, size: 16, color: AppColors.emerald),
          onPressed: () => _openStickerModal(p),
        ),
        IconButton(
          tooltip: 'Pricing',
          icon: const Icon(Icons.sell_outlined, size: 16, color: AppColors.amber600),
          onPressed: () => _openPriceModal(app, p),
        ),
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.slate500),
          onPressed: () => _openProductModal(p),
        ),
        if (app.session.role == UserRole.topManager)
          IconButton(
            tooltip: 'Delete commodity',
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.red),
            onPressed: () => _confirmDeleteProduct(app, p),
          ),
      ])),
    ]);
  }

  Widget _ledger(AppState app) {
    final txs = app.transactions.reversed.toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Inventory Ledger Flows',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.slate800)),
          const SizedBox(height: 12),
          Scrollbar(
            controller: _ledgerScroll,
            thumbVisibility: true,
            trackVisibility: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                controller: _ledgerScroll,
                scrollDirection: Axis.horizontal,
                child: DataTable(
              columnSpacing: 20,
              headingRowHeight: 40,
              columns: const [
                DataColumn(label: Text('Date & Time')),
                DataColumn(label: Text('Commodity')),
                DataColumn(label: Text('Flow')),
                DataColumn(label: Text('Unit Cost'), numeric: true),
                DataColumn(label: Text('Operator')),
                DataColumn(label: Text('Reason')),
              ],
              rows: txs.map((t) {
                final isIn = t.type == 'in';
                return DataRow(cells: [
                  DataCell(Text(fmtDateTime(t.timestamp),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.slate400))),
                  DataCell(Text(t.productName,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600))),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isIn
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(isIn ? '+${t.quantity}' : '${t.quantity}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isIn ? AppColors.emerald : AppColors.rose)),
                  )),
                  DataCell(Text(shs(t.buyingPriceAtTransaction),
                      style: const TextStyle(color: AppColors.slate500))),
                  DataCell(Text('${t.operatorName} (${t.operatorId})',
                      style: const TextStyle(fontSize: 11))),
                  DataCell(Text(t.reason.replaceAll('_', ' '),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.slate400))),
                ]);
              }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Modals ----------
  Future<void> _confirmDeleteProduct(AppState app, Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Commodity'),
        content: Text(
            'Permanently remove "${p.name}" (${p.sku}) from the catalog?\n\n'
            'This cannot be undone. Past sales records are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (app.deleteProduct(p.id)) {
      setState(() {});
      _banner('${p.name} removed from inventory.');
    }
  }

  void _openProductModal(Product? editing) {
    final app = context.read<AppState>();
    final name = TextEditingController(text: editing?.name ?? '');
    final sku = TextEditingController(text: editing?.sku ?? '');
    var category = editing?.category ?? (app.categories.firstOrNull ?? 'Seeds');
    final customCategory = TextEditingController();
    final buying =
        TextEditingController(text: editing?.buyingPrice.toString() ?? '');
    final wholesale = TextEditingController(
        text: editing?.wholesalePrice.toString() ?? '');
    final retail = TextEditingController(
        text: editing?.retailPrice.toString() ?? '');
    final unitLabel =
        TextEditingController(text: editing?.unitLabel ?? 'piece');
    final stock =
        TextEditingController(text: editing?.currentStock.toString() ?? '');
    final minStock =
        TextEditingController(text: editing?.minStockLevel.toString() ?? '5');
    final expiry = TextEditingController(text: editing?.expirationDate ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        return AlertDialog(
          title: Text(
              editing != null ? 'Edit Commodity' : 'Register New Commodity'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 460)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field('Commodity Name *', name),
                  Row(children: [
                    Expanded(child: _field('SKU (auto if empty)', sku)),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => setModal(() =>
                          sku.text = app.autoSku(category, name.text)),
                      icon: const Icon(Icons.auto_awesome, size: 12),
                      label: const Text('Auto', style: TextStyle(fontSize: 11)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final options = <String>[...app.categories];
                    if (!options.contains(category)) {
                      options.insert(0, category);
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: options.contains(category) ? category : null,
                      decoration: const InputDecoration(labelText: 'Category *'),
                      items: options
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setModal(() => category = v ?? category),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: customCategory,
                        decoration: const InputDecoration(
                          labelText: 'Custom category',
                          hintText: 'e.g. Greenhouses, Animal Feed',
                        ),
                        onSubmitted: (v) {
                          final n = v.trim();
                          if (n.isEmpty) return;
                          if (app.ensureCategory(n) == n) {
                            setModal(() {
                              category = n;
                              customCategory.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        final n = customCategory.text.trim();
                        if (n.isEmpty) return;
                        app.ensureCategory(n);
                        setModal(() {
                          category = n;
                          customCategory.clear();
                        });
                      },
                      child: const Text('Add'),
                    ),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Pick a built-in category or type a new one and tap Add.',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.slate400)),
                    ),
                  ),
                  _field('Buying cost (shs) *', buying, num: true),
                  const SizedBox(height: 4),
                  _field('Base unit *', unitLabel, onChanged: () => setModal(() {})),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Base unit is what you sell one of, e.g. piece, kg, litre.',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.slate400)),
                    ),
                  ),
                  Row(children: [
                    Expanded(
                        child: _field('Limit price (shs) *', wholesale,
                            num: true)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _field(
                            'Selling price / ${unitLabel.text.trim().isEmpty ? 'unit' : unitLabel.text.trim()} *',
                            retail,
                            num: true)),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Limit price is the minimum a worker may sell at (POS checkout floor). Selling price is the default shown at POS.',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.slate400)),
                    ),
                  ),
                  Row(children: [
                    Expanded(
                        child: _field('Stock quantity (${unitLabel.text.trim().isEmpty ? 'units' : unitLabel.text.trim()}) *',
                            stock,
                            num: true)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _field('Low threshold *', minStock, num: true)),
                  ]),
                  const SizedBox(height: 8),
                  _dateField('Expiration Date', expiry, ctx, setModal),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  _banner('Commodity name is required.', err: true);
                  return;
                }
                final exp =
                    expiry.text.trim().isEmpty ? null : expiry.text.trim();
                final buyingVal = num.tryParse(buying.text) ?? 0;
                final wholesaleVal =
                    num.tryParse(wholesale.text.trim()) ?? buyingVal;
                final retailVal =
                    num.tryParse(retail.text.trim()) ?? wholesaleVal;
                // Price integrity: cost ≤ limit ≤ selling. Blocks saving a
                // product that could later be sold at or below cost, which is
                // what corrupts POS profit/revenue figures downstream.
                if (buyingVal <= 0) {
                  _banner('Buying cost must be greater than 0.', err: true);
                  return;
                }
                if (wholesaleVal < buyingVal) {
                  _banner(
                      'Limit price cannot be below the buying cost '
                      '(${shs(buyingVal)}).',
                      err: true);
                  return;
                }
                if (retailVal < wholesaleVal) {
                  _banner(
                      'Selling price cannot be below the limit price '
                      '(${shs(wholesaleVal)}).',
                      err: true);
                  return;
                }
                final unit =
                    unitLabel.text.trim().isEmpty ? 'piece' : unitLabel.text.trim();
                final custom = customCategory.text.trim();
                if (custom.isNotEmpty) {
                  category = app.ensureCategory(custom);
                } else {
                  category = app.ensureCategory(category);
                }
                if (editing != null) {
                  final upd = editing.copy()
                    ..name = name.text.trim()
                    ..sku = sku.text.trim()
                    ..category = category
                    ..buyingPrice = buyingVal
                    ..wholesalePrice = wholesaleVal
                    ..retailPrice = retailVal
                    ..unitLabel = unit
                    ..currentStock = num.tryParse(stock.text) ?? 0
                    ..minStockLevel = num.tryParse(minStock.text) ?? 0
                    ..expirationDate = exp;
                  if (upd.sellingPrice < retailVal) upd.sellingPrice = retailVal;
                  app.updateProduct(upd);
                } else {
                  app.addProduct(
                    name: name.text.trim(),
                    sku: sku.text.trim(),
                    category: category,
                    buyingPrice: buyingVal,
                    wholesalePrice: wholesaleVal,
                    retailPrice: retailVal,
                    unitLabel: unit,
                    currentStock: num.tryParse(stock.text) ?? 0,
                    minStockLevel: num.tryParse(minStock.text) ?? 0,
                    expirationDate: exp,
                  );
                }
                Navigator.pop(ctx);
                _banner(editing != null
                    ? 'Commodity updated.'
                    : 'Commodity registered.');
              },
              child: Text(editing != null ? 'Save Changes' : 'Register'),
            ),
          ],
        );
      }),
    );
  }

  void _openRestockModal(AppState app, Product p) {
    final qty = TextEditingController();
    final buying = TextEditingController(text: p.buyingPrice.toString());
    final expiry = TextEditingController(text: p.expirationDate ?? '');
    var newBatch = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        final differs = expiry.text.isNotEmpty && expiry.text != p.expirationDate;
        return AlertDialog(
          title: Text('Replenish: ${p.name}',
              style: const TextStyle(fontSize: 16)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 360)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field('${p.unitLabel[0].toUpperCase()}${p.unitLabel.substring(1)}s to add *',
                  qty, num: true),
              _field('Unit buying cost (shs)', buying, num: true),
              _dateField('Expiration Date', expiry, ctx, setModal),
              if (differs)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: newBatch,
                  onChanged: (v) => setModal(() => newBatch = v ?? false),
                  title: const Text('Split into a new separate batch?',
                      style: TextStyle(fontSize: 12)),
                  subtitle: const Text(
                      'Different expiry — track this batch separately.',
                      style: TextStyle(fontSize: 10)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final q = num.tryParse(qty.text);
                if (q == null || q <= 0) return;
                final res = app.restockProduct(
                  p.id,
                  q,
                  buyingPrice:
                      buying.text.isEmpty ? null : num.tryParse(buying.text),
                  newExpirationDate: expiry.text.isEmpty ? null : expiry.text,
                  createNewBatch: newBatch,
                );
                Navigator.pop(ctx);
                if (res != null && res['type'] == 'new_batch') {
                  final np = res['product'] as Product;
                  _banner('Created separate batch "${np.name}" (${np.sku}).');
                } else {
                  _banner('Replenished $q ${p.unitLabel}(s) of "${p.name}"!');
                }
              },
              child: const Text('Confirm Restock'),
            ),
          ],
        );
      }),
    );
  }

  void _openPriceModal(AppState app, Product p) {
    final buying = TextEditingController(text: p.buyingPrice.toString());
    final wholesale = TextEditingController(text: p.wholesalePrice.toString());
    final retail = TextEditingController(text: p.retailPrice.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pricing: ${p.name}', style: const TextStyle(fontSize: 16)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: Responsive.dialogWidth(ctx, max: 320)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field('Buying cost (shs) *', buying, num: true),
            _field('Limit price (shs) *', wholesale, num: true),
            _field('Selling price / ${p.unitLabel} (shs) *', retail, num: true),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Limit price is the POS checkout floor — actual selling price can be raised at checkout but not below it.',
                  style: TextStyle(fontSize: 10, color: AppColors.slate400)),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final w = num.tryParse(wholesale.text);
              final r = num.tryParse(retail.text);
              final b = num.tryParse(buying.text) ?? p.buyingPrice;
              if (w == null || r == null) return;
              // Price integrity: cost ≤ limit ≤ selling.
              if (b <= 0) {
                _banner('Buying cost must be greater than 0.', err: true);
                return;
              }
              if (w < b) {
                _banner(
                    'Limit price cannot be below the buying cost (${shs(b)}).',
                    err: true);
                return;
              }
              if (r < w) {
                _banner(
                    'Selling price cannot be below the limit price (${shs(w)}).',
                    err: true);
                return;
              }
              final upd = p.copy()
                ..buyingPrice = b
                ..wholesalePrice = w
                ..retailPrice = r;
              if (upd.sellingPrice < r) upd.sellingPrice = r;
              app.updateProduct(upd);
              Navigator.pop(ctx);
              _banner('Updated pricing for ${p.name}!');
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _openStickerModal(Product p) {
    var count = 12;
    var branding = true;
    var showExpiry = p.expirationDate != null;
    final price = TextEditingController(text: p.retailPrice.toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        final priceVal = num.tryParse(price.text) ?? p.retailPrice;
        return AlertDialog(
          title: const Text('Barcode Sticker Printer',
              style: TextStyle(fontSize: 16)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 460)),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Preview
                Container(
                  width: 220,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      border: Border.all(color: AppColors.slate800, width: 2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Column(children: [
                    if (branding)
                      Text(AppBranding.receiptHeader,
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w900)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    BarcodeWidget(
                      barcode: Barcode.code39(),
                      data: p.sku,
                      width: 160,
                      height: 34,
                      drawText: false,
                    ),
                    Text(p.sku, style: const TextStyle(fontSize: 8)),
                    const SizedBox(height: 4),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showExpiry && p.expirationDate != null)
                                  Text('EXP: ${p.expirationDate}',
                                      style: const TextStyle(fontSize: 7)),
                                const Text('LOC: MAIN STK',
                                    style: TextStyle(fontSize: 7)),
                              ]),
                          Text('shs ${money(priceVal)}',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w900)),
                        ]),
                  ]),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Text('Count: '),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '$count',
                      onChanged: (v) => setModal(() => count = v.round()),
                    ),
                  ),
                  Text('$count pcs'),
                ]),
                _field('Label price (shs)', price, num: true,
                    onChanged: () => setModal(() {})),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: branding,
                  onChanged: (v) => setModal(() => branding = v),
                  title: Text('Include ${AppBranding.labelBranding} branding',
                      style: TextStyle(fontSize: 12)),
                ),
                if (p.expirationDate != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: showExpiry,
                    onChanged: (v) => setModal(() => showExpiry = v),
                    title: const Text('Show expiration date',
                        style: TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
          ),
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
                OutlinedButton.icon(
                  onPressed: () => PrintService.printStickers(p,
                      count: count,
                      price: priceVal,
                      showBranding: branding,
                      showExpiry: showExpiry,
                      share: true),
                  icon: const Icon(Icons.ios_share, size: 14),
                  label: const Text('Export'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.slate900),
                  onPressed: () => PrintService.printStickers(p,
                      count: count,
                      price: priceVal,
                      showBranding: branding,
                      showExpiry: showExpiry),
                  icon: const Icon(Icons.print, size: 14),
                  label: Text('Print ($count)'),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  void _openCategoryManager() {
    final app = context.read<AppState>();
    final newCat = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
        return AlertDialog(
          title: const Text('Manage Categories'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: Responsive.dialogWidth(ctx, max: 380)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'Built-in agri categories are listed below. Add your own custom categories anytime.',
                style: TextStyle(fontSize: 11, color: AppColors.slate500),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: newCat,
                    decoration: const InputDecoration(
                      hintText: 'Custom category e.g. Greenhouses, Animal Feed',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (app.addCategory(newCat.text)) {
                      newCat.clear();
                      setModal(() {});
                    }
                  },
                  child: const Text('Add'),
                ),
              ]),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    children: app.categories
                        .map((cat) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(cat,
                                  style: const TextStyle(fontSize: 13)),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 16),
                                      onPressed: () async {
                                        final renamed =
                                            await _promptText('Rename', cat);
                                        if (renamed != null &&
                                            app.editCategory(cat, renamed)) {
                                          setModal(() {});
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 16, color: AppColors.red),
                                      onPressed: () {
                                        if (app.categories.length <= 1) return;
                                        app.deleteCategory(cat);
                                        setModal(() {});
                                      },
                                    ),
                                  ]),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        );
      }),
    );
  }

  Future<String?> _promptText(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {bool num = false, VoidCallback? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: num ? TextInputType.number : TextInputType.text,
        inputFormatters: num ? const [NoLeadingZeroFormatter()] : null,
        onChanged: onChanged == null ? null : (_) => onChanged(),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _dateField(String label, TextEditingController c, BuildContext ctx,
      void Function(void Function()) setModal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
          hintText: 'YYYY-MM-DD',
        ),
        onTap: () async {
          final init = DateTime.tryParse(c.text) ?? DateTime.now();
          final picked = await showDatePicker(
            context: ctx,
            initialDate: init,
            firstDate: DateTime(2024),
            lastDate: DateTime(2032),
          );
          if (picked != null) {
            setModal(() => c.text =
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
          }
        },
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
