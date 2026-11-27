import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chad_avs_pos_3d/database.dart';
import 'package:chad_avs_pos_3d/services.dart';
import 'package:chad_avs_pos_3d/theme_3d.dart';

class UpperMiddleExchangeRateBanner extends StatelessWidget {
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;
  final VoidCallback? onUpdated;

  const UpperMiddleExchangeRateBanner({
    super.key,
    required this.rateController,
    required this.pricingService,
    this.onUpdated,
  });

  Future<void> _openEditDialog(BuildContext context) async {
    if (!rateController.canEditExchangeRate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعديل سعر الصرف متاح للمدير حصراً')),
      );
      return;
    }

    final ctrl = TextEditingController(
      text: rateController.usdToNewSyp.toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: App3DTheme.cardDark,
        title: const Text('تحديث سعر الصرف (للمدير حصراً)'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'سعر 1 دولار بالليرة السورية الجديدة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text.trim());
              if (val == null || val <= 0) return;
              final done =
                  await pricingService.updateExchangeRateAndRepriceAllProducts(val);
              if (ctx.mounted) Navigator.pop(ctx, done);
            },
            child: const Text('تحديث الكل'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (ok == true) onUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = rateController.canEditExchangeRate;
    final rate = rateController.usdToNewSyp;
    final ratio = rateController.oldToNewSypRatio;

    return Interactive3DCard(
      onTap: canEdit ? () => _openEditDialog(context) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF162A42),
      child: Row(
        children: [
          const Icon(
            Icons.currency_exchange_rounded,
            color: App3DTheme.accentGold,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'سعر الصرف (أعلى منتصف الصفحة): 1\$ = ${rate.toStringAsFixed(2)} جديدة (${(rate * ratio).toStringAsFixed(0)} قديمة)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            canEdit ? 'تعديل (مدير)' : 'عرض فقط',
            style: TextStyle(
              fontSize: 11,
              color: canEdit ? App3DTheme.accentCyan : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

class Inventory3DScreen extends StatefulWidget {
  final AppDatabase db;
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;

  const Inventory3DScreen({
    super.key,
    required this.db,
    required this.rateController,
    required this.pricingService,
  });

  @override
  State<Inventory3DScreen> createState() => _Inventory3DScreenState();
}

class _Inventory3DScreenState extends State<Inventory3DScreen> {
  String _search = '';
  bool _onlyLowStock = false;

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: App3DTheme.navyHeader,
        title: const Text('المخزون والجرد 3D — CHAD A.V.S'),
      ),
      body: StreamBuilder<List<Product>>(
        stream: widget.db.select(widget.db.products).watch(),
        builder: (context, snap) {
          final items = (snap.data ?? []).where((p) {
            if (p.isDeleted) return false;
            final matchText = _search.isEmpty ||
                p.name.toLowerCase().contains(_search.toLowerCase()) ||
                (p.barcode ?? '').contains(_search);
            final matchStock =
                !_onlyLowStock || p.totalQuantity <= p.minStockAlert;
            return matchText && matchStock;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v.trim()),
                      decoration: const InputDecoration(
                        hintText: 'بحث بالاسم أو الباركود...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('النواقص'),
                    selected: _onlyLowStock,
                    onSelected: (v) => setState(() => _onlyLowStock = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              UpperMiddleExchangeRateBanner(
                rateController: widget.rateController,
                pricingService: widget.pricingService,
                onUpdated: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد مواد في المخزون حالياً')),
                )
              else
                ...items.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Interactive3DCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'الكمية: ${p.totalQuantity}${p.unitName}',
                                style: TextStyle(
                                  color: p.totalQuantity <= p.minStockAlert
                                      ? App3DTheme.dangerRed
                                      : App3DTheme.successGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'بيع: \$${p.saleUsd.toStringAsFixed(2)} | ${(p.saleUsd * rate).toStringAsFixed(1)} جديدة \vert{} ${(p.saleUsd * rate * ratio).toStringAsFixed(0)} قديمة',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AddProduct3DScreen extends StatefulWidget {
  final AppDatabase db;
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;

  const AddProduct3DScreen({
    super.key,
    required this.db,
    required this.rateController,
    required this.pricingService,
  });

  @override
  State<AddProduct3DScreen> createState() => _AddProduct3DScreenState();
}

class _AddProduct3DScreenState extends State<AddProduct3DScreen> {
  final _nameCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '10');
  final _costUsdCtrl = TextEditingController(text: '10');
  final _marginCtrl = TextEditingController(text: '25');
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _qtyCtrl.dispose();
    _costUsdCtrl.dispose();
    _marginCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final costUsd = double.tryParse(_costUsdCtrl.text.trim()) ?? 0;
    final margin = double.tryParse(_marginCtrl.text.trim()) ?? 0;
    final saleUsd = costUsd * (1 + (margin / 
                              /database.dart';
import 'package:chad_avs_pos_3d/services.dart';
import 'package:chad_avs_pos_3d/theme_3d.dart';

// ============================================================================
// 1. ALL 3D SCREENS (UPPER-MIDDLE EXCHANGE RATE, MANAGER-ONLY EDIT)
// ============================================================================

class UpperMiddleExchangeRateBanner extends StatelessWidget {
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;
  final VoidCallback? onUpdated;

  const UpperMiddleExchangeRateBanner({
    super.key,
    required this.rateController,
    required this.pricingService,
    this.onUpdated,
  });

  Future<void> _openEditDialog(BuildContext context) async {
    if (!rateController.canEditExchangeRate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعديل سعر الصرف متاح للمدير حصراً')),
      );
      return;
    }

    final ctrl = TextEditingController(
      text: rateController.usdToNewSyp.toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: App3DTheme.cardDark,
        title: const Text('تحديث سعر الصرف (للمدير حصراً)'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'سعر 1 دولار بالليرة السورية الجديدة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text.trim());
              if (val == null || val <= 0) return;
              final done =
                  await pricingService.updateExchangeRateAndRepriceAllProducts(val);
              if (ctx.mounted) Navigator.pop(ctx, done);
            },
            child: const Text('تحديث الكل'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (ok == true) onUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = rateController.canEditExchangeRate;
    final rate = rateController.usdToNewSyp;
    final ratio = rateController.oldToNewSypRatio;

    return Interactive3DCard(
      onTap: canEdit ? () => _openEditDialog(context) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF162A42),
      child: Row(
        children: [
          const Icon(
            Icons.currency_exchange_rounded,
            color: App3DTheme.accentGold,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'سعر الصرف (أعلى منتصف الصفحة): 1\$ = ${rate.toStringAsFixed(2)} جديدة (${(rate * ratio).toStringAsFixed(0)} قديمة)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            canEdit ? 'تعديل (مدير)' : 'عرض فقط',
            style: TextStyle(
              fontSize: 11,
              color: canEdit ? App3DTheme.accentCyan : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

class Inventory3DScreen extends StatefulWidget {
  final AppDatabase db;
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;

  const Inventory3DScreen({
    super.key,
    required this.db,
    required this.rateController,
    required this.pricingService,
  });

  @override
  State<Inventory3DScreen> createState() => _Inventory3DScreenState();
}

class _Inventory3DScreenState extends State<Inventory3DScreen> {
  String _search = '';
  bool _onlyLowStock = false;

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: App3DTheme.navyHeader,
        title: const Text('المخزون والجرد 3D — CHAD A.V.S'),
      ),
      body: StreamBuilder<List<Product>>(
        stream: widget.db.select(widget.db.products).watch(),
        builder: (context, snap) {
          final items = (snap.data ?? []).where((p) {
            if (p.isDeleted) return false;
            final matchText = _search.isEmpty ||
                p.name.toLowerCase().contains(_search.toLowerCase()) ||
                (p.barcode ?? '').contains(_search);
            final matchStock = !_onlyLowStock || p.totalQuantity <= p.minStockAlert;
            return matchText && matchStock;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v.trim()),
                      decoration: const InputDecoration(
                        hintText: 'بحث بالاسم أو الباركود...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('النواقص'),
                    selected: _onlyLowStock,
                    onSelected: (v) => setState(() => _onlyLowStock = v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              UpperMiddleExchangeRateBanner(
                rateController: widget.rateController,
                pricingService: widget.pricingService,
                onUpdated: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('لا توجد مواد في المخزون حالياً')),
                )
              else
                ...items.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Interactive3DCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'الكمية: ${p.totalQuantity} ${p.unitName}',
                                style: TextStyle(
                                  color: p.totalQuantity <= p.minStockAlert
                                      ? App3DTheme.dangerRed
                                      : App3DTheme.successGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'بيع: \$${p.saleUsd.toStringAsFixed(2)} | ${(p.saleUsd * rate).toStringAsFixed(1)} جديدة | ${(p.saleUsd * rate * ratio).toStringAsFixed(0)} قديمة',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AddProduct3DScreen extends StatefulWidget {
  final AppDatabase db;
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;

  const AddProduct3DScreen({
    super.key,
    required this.db,
    required this.rateController,
    required this.pricingService,
  });

  @override
  State<AddProduct3DScreen> createState() => _AddProduct3DScreenState();
}

class _AddProduct3DScreenState extends State<AddProduct3DScreen> {
  final _nameCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '10');
  final _costUsdCtrl = TextEditingController(text: '10');
  final _marginCtrl = TextEditingController(text: '25');
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _qtyCtrl.dispose();
    _costUsdCtrl.dispose();
    _marginCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final costUsd = double.tryParse(_costUsdCtrl.text.trim()) ?? 0;
    final margin = double.tryParse(_marginCtrl.text.trim()) ?? 0;
    final saleUsd = costUsd * (1 + (margin / 100));
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;

    await widget.db.into(widget.db.products).insert(
          ProductsCompanion.insert(
            name: name,
            barcode: Value(_barcodeCtrl.text.trim().isEmpty
                ? null
                : _barcodeCtrl.text.trim()),
            totalQuantity: Value(qty),
            costUsd: Value(costUsd),
            saleUsd: Value(saleUsd),
            costNewSyp: Value(costUsd * rate),
            saleNewSyp: Value(saleUsd * rate),
            costOldSyp: Value(costUsd * rate * ratio),
            saleOldSyp: Value(saleUsd * rate * ratio),
            profitMarginPercent: Value(margin),
            notes: Value(_notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim()),
            isSynced: const Value(false),
          ),
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة المادة وتسعيرها بالعملات الثلاث')),
      );
      _nameCtrl.clear();
      _barcodeCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final costUsd = double.tryParse(_costUsdCtrl.text.trim()) ?? 0;
    final margin = double.tryParse(_marginCtrl.text.trim()) ?? 0;
    final saleUsd = costUsd * (1 + (margin / 100));
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: App3DTheme.navyHeader,
        title: const Text('إضافة مادة وتسعيرها 3D — CHAD A.V.S'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          UpperMiddleExchangeRateBanner(
            rateController: widget.rateController,
            pricingService: widget.pricingService,
            onUpdated: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          Interactive3DCard(
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المادة'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _barcodeCtrl,
                  decoration: const InputDecoration(labelText: 'الباركود / QR'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'الكمية'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _costUsdCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'التكلفة (\$)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _marginCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'الربح %'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                const SizedBox(height: 12),
                Text(
                  'سعر البيع المقدر: \$${saleUsd.toStringAsFixed(2)} | ${(saleUsd * rate).toStringAsFixed(1)} جديدة | ${(saleUsd * rate * ratio).toStringAsFixed(0)} قديمة',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: App3DTheme.accentGold,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveProduct,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('حفظ المادة'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PosInvoices3DScreen extends StatefulWidget {
  final AppDatabase db;
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;
  final InvoiceService invoiceService;
  final PdfExportService pdfService;

  const PosInvoices3DScreen({
    super.key,
    required this.db,
    required this.rateController,
    required this.pricingService,
    required this.invoiceService,
    required this.pdfService,
  });

  @override
  State<PosInvoices3DScreen> createState() => _PosInvoices3DScreenState();
}

class _PosInvoices3DScreenState extends State<PosInvoices3DScreen> {
  String _invoiceType = 'sale';
  final _subtotalCtrl = TextEditingController(text: '100');
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '100');

  @override
  void dispose() {
    _subtotalCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitInvoice() async {
    final sub = double.tryParse(_subtotalCtrl.text.trim()) ?? 0;
    final disc = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    final paid = double.tryParse(_paidCtrl.text.trim()) ?? 0;
    if (sub <= 0) return;

    await widget.invoiceService.createInvoice(
      invoiceType: _invoiceType,
      branchId: 1,
      subtotalUsd: sub,
      discountUsd: disc,
      paidUsd: paid,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الفاتورة وتحديث الأرصدة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: App3DTheme.navyHeader,
        title: const Text('الفواتير ونقاط البيع 3D — CHAD A.V.S'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          DropdownButton<String>(
            value: _invoiceType,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'sale', child: Text('فاتورة بيع')),
              DropdownMenuItem(value: 'purchase', child: Text('فاتورة شراء')),
              DropdownMenuItem(value: 'saleReturn', child: Text('مرتجع بيع')),
              DropdownMenuItem(
                  value: 'purchaseReturn', child: Text('مرتجع شراء')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _invoiceType = v);
            },
          ),
          const SizedBox(height: 10),
          UpperMiddleExchangeRateBanner(
            rateController: widget.rateController,
            pricingService: widget.pricingService,
            onUpdated: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          Interactive3DCard(
            child: Column(
              children: [
                TextField(
                  controller: _subtotalCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المجموع (\$)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _discountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الخصم (\$)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paidCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'المدفوع نقداً (\$)'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitInvoice,
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('حفظ الفاتورة'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Invoice>>(
            stream: widget.db.select(widget.db.invoices).watch(),
            builder: (context, snap) {
              final list = snap.data ?? [];
              return Column(
                children: list
                    .map(
                      (inv) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Interactive3DCard(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${inv.invoiceNumber} (${inv.invoiceType})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'الصافي: \$${inv.totalUsd.toStringAsFixed(2)} | متبقي: \$${inv.remainingUsd.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 12),
                                  totalQuantity: Value(qty),
            costUsd: Value(costUsd),
            saleUsd: Value(saleUsd),
            costNewSyp: Value(costUsd * rate),
            saleNewSyp: Value(saleUsd * rate),
            costOldSyp: Value(costUsd * rate * ratio),
            saleOldSyp: Value(saleUsd * rate * ratio),
            profitMarginPercent: Value(margin),
            notes: Value(_notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim()),
            isSynced: const Value(false),
          ),
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('تمت إضافة المادة وتسعيرها بالعملات الثلاث')),
      );
      _nameCtrl.clear();
      _barcodeCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final costUsd = double.tryParse(_costUsdCtrl.text.trim()) ?? 0;
    final margin = double.tryParse(_marginCtrl.text.trim()) ?? 0;
    final saleUsd = costUsd * (1 + (margin / 100));
    final rate = widget.rateController.usdToNewSyp;
    final ratio = widget.rateController.oldToNewSypRatio;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: App3DTheme.navyHeader,
        title: const Text('إضافة مادة وتسعيرها 3D — CHAD A.V.S'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          UpperMiddleExchangeRateBanner(
            rateController: widget.rateController,
            pricingService: widget.pricingService,
            onUpdated: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          Interactive3DCard(
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المادة'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _barcodeCtrl,
                  decoration: const InputDecoration(labelText: 'الباركود / QR'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'الكمية'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _costUsdCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'التكلفة (\$)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _marginCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration:
                            const InputDecoration(labelText: 'الربح %'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                const SizedBox(height: 12),
                Text(
                  'سعر البيع المقدر: \$${saleUsd.toStringAsFixed(2)} | ${(saleUsd * rate).toStringAsFixed(1)} جديدة | ${(saleUsd * rate * ratio).toStringAsFixed(0)} قديمة',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: App3DTheme.accentGold,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveProduct,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('حفظ المادة'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PosInvoices3DScreen extends StatefulWidget {
  final AppDatabase db;
  final ExchangeRateController rateController;
  final PricingSyncService pricingService;
  final InvoiceService invoiceService;
  final PdfExportService pdfService;

  const PosInvoices3DScreen({
    super.key,
    required this.db,
    required this.rateController,
    required this.pricingService,
    required this.invoiceService,
    required this.pdfService,
  });

  @override
  State<PosInvoices3DScreen> createState() => _PosInvoices3DScreenState();
}

class _PosInvoices3DScreenState extends State<PosInvoices3DScreen> {
  String _invoiceType = 'sale';
  final _subtotalCtrl = TextEditingController(text: '100');
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '100');

  @override
  void dispose() {
    _subtotalCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitInvoice() async {
    final sub = double.tryParse(_subtotalCtrl.text.trim()) ?? 0;
    final disc = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    final paid = double.tryParse(_paidCtrl.text.trim()) ?? 0;
    if (sub <= 0) return;

    await widget.invoiceService.createInvoice(
      invoiceType: _invoiceType,
      branchId: 1,
      subtotalUsd: sub,
      discountUsd: disc,
      paidUsd: paid,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الفاتورة وتحديث الأرصدة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = widget.rateController.usdToNewSyp;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: App3DTheme.navyHeader,
        title: const Text('الفواتير ونقاط البيع 3D — CHAD A.V.S'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          DropdownButton<String>(
            value: _invoiceType,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'sale', child: Text('فاتورة بيع')),
              DropdownMenuItem(value: 'purchase', child: Text('فاتورة شراء')),
              DropdownMenuItem(value: 'saleReturn', child: Text('مرتجع بيع')),
              DropdownMenuItem(
                  value: 'purchaseReturn', child: Text('مرتجع شراء')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _invoiceType = v);
            },
          ),
          const SizedBox(height: 10),
          UpperMiddleExchangeRateBanner(
            rateController: widget.rateController,
            pricingService: widget.pricingService,
            onUpdated: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          Interactive3DCard(
            child: Column(
              children: [
                TextField(
                  controller: _subtotalCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المجموع (\$)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _discountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الخصم (\$)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paidCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'المدفوع نقداً (\$)'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitInvoice,
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('حفظ الفاتورة'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Invoice>>(
            stream: widget.db.select(widget.db.invoices).watch(),
            builder: (context, snap) {
              final list = snap.data ?? [];
              return Column(
                children: list
                    .map(
                      (inv) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Interactive3DCard(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${inv.invoiceNumber} (${inv.invoiceType})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
        
