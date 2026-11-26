import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:chad_avs_pos_3d/database.dart';

// ============================================================================
// 1. CORE SERVICES (PRICING, INVOICES, CASHBOX, BRANCHES/USERS, SYNC, PDF)
// ============================================================================

class PricingSyncService {
  final AppDatabase db;
  final ExchangeRateController rateController;

  PricingSyncService({
    required this.db,
    required this.rateController,
  });

  Future<bool> updateExchangeRateAndRepriceAllProducts(double newUsdRate) async {
    if (!rateController.canEditExchangeRate) return false;
    final accepted = rateController.updateUsdRate(newUsdRate);
    if (!accepted) return false;

    final ratio = rateController.oldToNewSypRatio;

    await db.transaction(() async {
      await db.update(db.systemSettings).write(
            SystemSettingsCompanion(
              usdToNewSypRate: Value(newUsdRate),
              oldToNewSypRatio: Value(ratio),
            ),
          );

      final allProducts = await db.select(db.products).get();
      for (final prod in allProducts) {
        final costNew = prod.costUsd * newUsdRate;
        final saleNew = prod.saleUsd * newUsdRate;
        final costOld = costNew * ratio;
        final saleOld = saleNew * ratio;

        await (db.update(db.products)..where((t) => t.id.equals(prod.id))).write(
          ProductsCompanion(
            costNewSyp: Value(costNew),
            saleNewSyp: Value(saleNew),
            costOldSyp: Value(costOld),
            saleOldSyp: Value(saleOld),
            isSynced: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });

    return true;
  }
}

class InvoiceService {
  final AppDatabase db;
  final ExchangeRateController rateController;

  InvoiceService({
    required this.db,
    required this.rateController,
  });

  Future<int> createInvoice({
    required String invoiceType,
    required int branchId,
    int? accountId,
    required double subtotalUsd,
    required double discountUsd,
    required double paidUsd,
    String? notes,
  }) async {
    final netTotal = (subtotalUsd - discountUsd).clamp(0.0, double.infinity);
    final remaining = (netTotal - paidUsd).clamp(0.0, double.infinity);
    final rate = rateController.usdToNewSyp;
    final ratio = rateController.oldToNewSypRatio;
    final invNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';

    return db.transaction(() async {
      final id = await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              invoiceNumber: invNumber,
              invoiceType: invoiceType,
              branchId: Value(branchId),
              accountId: Value(accountId),
              subtotalUsd: Value(subtotalUsd),
              discountUsd: Value(discountUsd),
              totalUsd: Value(netTotal),
              paidUsd: Value(paidUsd),
              remainingUsd: Value(remaining),
              exchangeRateUsed: Value(rate),
              notes: Value(notes),
              isSynced: const Value(false),
            ),
          );

      if (accountId != null && remaining > 0) {
        final accList = await (db.select(db.accounts)
              ..where((t) => t.id.equals(accountId)))
            .get();
        if (accList.isNotEmpty) {
          final acc = accList.first;
          final nextBal = acc.balanceUsd + remaining;
          await (db.update(db.accounts)..where((t) => t.id.equals(acc.id))).write(
            AccountsCompanion(
              balanceUsd: Value(nextBal),
              isSynced: const Value(false),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      if (paidUsd > 0) {
        final entryType =
            (invoiceType == 'sale' || invoiceType == 'purchaseReturn')
                ? 'deposit'
                : 'withdraw';
        await db.into(db.cashboxTransactions).insert(
              CashboxTransactionsCompanion.insert(
                entryType: entryType,
                category: Value('فاتورة $invNumber'),
                amountUsd: Value(paidUsd),
                amountNewSyp: Value(paidUsd * rate),
                amountOldSyp: Value(paidUsd * rate * ratio),
                notes: Value(notes ?? invoiceType),
                isSynced: const Value(false),
              ),
            );
      }

      return id;
    });
  }
}

class CashboxService {
  final AppDatabase db;
  final ExchangeRateController rateController;

  CashboxService({
    required this.db,
    required this.rateController,
  });

  Future<void> recordCashEntry({
    required String entryType,
    required String category,
    required double amountUsd,
    String? notes,
  }) async {
    final rate = rateController.usdToNewSyp;
    final ratio = rateController.oldToNewSypRatio;

    await db.into(db.cashboxTransactions).insert(
          CashboxTransactionsCompanion.insert(
            entryType: entryType,
            category: Value(category),
            amountUsd: Value(amountUsd),
            amountNewSyp: Value(amountUsd * rate),
            amountOldSyp: Value(amountUsd * rate * ratio),
            notes: Value(notes),
            isSynced: const Value(false),
          ),
        );
  }
}

class BranchesUsersService {
  final AppDatabase db;
  final ExchangeRateController rateController;

  BranchesUsersService({
    required this.db,
    required this.rateController,
  });

  Future<void> addBranch({
    required String name,
    required String locationType,
    String? address,
  }) async {
    await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: name,
            locationType: Value(locationType),
            address: Value(address),
            isSynced: const Value(false),
          ),
        );
  }

  Future<void> addUser({
    required String fullName,
    required String phone,
    required UserRole role,
    int? branchId,
  }) async {
    await db.into(db.systemUsers).insert(
          SystemUsersCompanion.insert(
            fullName: fullName,
            phone: phone,
            role: Value(role.name),
            branchId: Value(branchId),
            isSynced: const Value(false),
          ),
        );
  }
}

class SyncBackupService {
  final AppDatabase db;
  final ExchangeRateController rateController;

  SyncBackupService({
    required this.db,
    required this.rateController,
  });

  Future<int> pushPendingRecords() async {
    int count = 0;
    await db.transaction(() async {
      final unsyncedProds = await (db.select(db.products)
            ..where((t) => t.isSynced.equals(false)))
          .get();
      count += unsyncedProds.length;
      await (db.update(db.products)..where((t) => t.isSynced.equals(false)))
          .write(const ProductsCompanion(isSynced: Value(true)));

      final unsyncedInvs = await (db.select(db.invoices)
            ..where((t) => t.isSynced.equals(false)))
          .get();
      count += unsyncedInvs.length;
      await (db.update(db.invoices)..where((t) => t.isSynced.equals(false)))
          .write(const InvoicesCompanion(isSynced: Value(true)));

      final unsyncedCash = await (db.select(db.cashboxTransactions)
            ..where((t) => t.isSynced.equals(false)))
          .get();
      count += unsyncedCash.length;
      await (db.update(db.cashboxTransactions)
            ..where((t) => t.isSynced.equals(false)))
          .write(const CashboxTransactionsCompanion(isSynced: Value(true)));
    });
    return count;
  }

  Future<void> rewindServerCursor({
    required Duration lookback,
    required int maxRecordsPerTable,
  }) async {
    final targetDate = DateTime.now().subtract(lookback);
    await db.update(db.systemSettings).write(
          SystemSettingsCompanion(serverSyncCursor: Value(targetDate)),
        );
    final limitVal = maxRecordsPerTable.clamp(1, 150);
    await (db.select(db.invoices)..limit(limitVal)).get();
  }
}

class CloudBackupSnapshot {
  final String backupId;
  final String phone;
  final DateTime createdAt;
  final int productsCount;
  final int invoicesCount;

  const CloudBackupSnapshot({
    required this.backupId,
    required this.phone,
    required this.createdAt,
    required this.productsCount,
    required this.invoicesCount,
  });
}

class BackupPrintService {
  final AppDatabase db;
  final ExchangeRateController rateController;

  BackupPrintService({
    required this.db,
    required this.rateController,
  });

  final Map<String, List>> _phoneBackupsStore = {};

  Future<CloudBackupSnapshot> createBackupByPhone(String phone) async {
    final normalizedPhone = phone.trim();
    final products = await db.select(db.products).get();
    final invoices = await db.select(db.invoices).get();
    final accounts = await db.select(db.accounts).get();
    final cashRows = await db.select(db.cashboxTransactions).get();

    final backupId = 'CHAD-AVS-BKP-${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'signature': 'CHAD A.V.S',
      'backupId': backupId,
      'phone': normalizedPhone,
      'createdAt': DateTime.now().toIso8601String(),
      'usdToNewSypRate': rateController.usdToNewSyp,
      'products': products.map((e) => e.toJson()).toList(),
      'invoices': invoices.map((e) => e.toJson()).toList(),
      'accounts': accounts.map((e) => e.toJson()).toList(),
      'cashbox': cashRows.map((e) => e.toJson()).toList(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, '$backupId.json'));
    await file.writeAsString(jsonEncode(payload));

    final list = _phoneBackupsStore.putIfAbsent(normalizedPhone, () => []);
    list.insert(0, payload);

    return CloudBackupSnapshot(
      backupId: backupId,
      phone: normalizedPhone,
      createdAt: DateTime.now(),
      productsCount: products.length,
      invoicesCount: invoices.length,
    );
  }

  List<CloudBackupSnapshot> listBackupsForPhone(String phone) {
    final entries = _phoneBackupsStore[phone.trim()] ?? const [];
    return entries.map((item) {
      return CloudBackupSnapshot(
        backupId: item['backupId'] as String? ?? '',
        phone: item['phone'] as String? ?? phone,
        createdAt: DateTime.tryParse(item['createdAt'] as String? ?? '') ??
            DateTime.now(),
        productsCount: (item['products'] as List?)?.length ?? 0,
        invoicesCount: (item['invoices'] as List?)?.length ?? 0,
      );
    }).toList();
  }

  bool deleteBackup(String phone, String backupId) {
    final entries = _phoneBackupsStore[phone.trim()];
    if (entries == null) return false;
    final before = entries.length;
    entries.removeWhere((e) => e['backupId'] == backupId);
    return entries.length < before;
  }

  Future<bool> restoreBackup(String phone, String backupId) async {
    final entries = _phoneBackupsStore[phone.trim()];
    if (entries == null) return false;
    final match = entries.where((e) => e['backupId'] == backupId).toList();
    if (match.isEmpty) return false;

    final rate = (match.first['usdToNewSypRate'] as num?)?.toDouble();
    if (rate != null && rate > 0) {
      rateController.updateUsdRate(rate);
      await db.update(db.systemSettings).write(
            SystemSettingsCompanion(usdToNewSypRate: Value(rate)),
          );
    }
    return true;
  }

  String buildReceiptText({
    required String storeName,
    required String invoiceNumber,
    required String invoiceType,
    required double totalUsd,
    required double paidUsd,
  }) {
    final rate = rateController.usdToNewSyp;
    final ratio = rateController.oldToNewSypRatio;
    final newSyp = totalUsd * rate;
    final oldSyp = newSyp * ratio;

    return [
      '==============================',
      'CHAD A.V.S — $storeName',
      'سند فاتورة: $invoiceNumber ($invoiceType)',
      'التاريخ: ${DateTime.now().toString().substring(0, 16)}',
      '------------------------------',
      'الإجمالي: \$${totalUsd.toStringAsFixed(2)}',
      'بالليرة الجديدة: ${newSyp.toStringAsFixed(1)}',
      'بالليرة القديمة: ${oldSyp.toStringAsFixed(0)}',
      'المدفوع: \$${paidUsd.toStringAsFixed(2)}',
      'سعر الصرف: 1\$ = ${rate.toStringAsFixed(2)} جديدة',
      'توقيع النظام: CHAD A.V.S',
      '==============================',
    ].join('\n');
  }
}

class PdfReportRow {
  final List<String> cells;
  const PdfReportRow(this.cells);
}

class PdfExportService {
  Future<void> generateAndPreviewPdf({
    required String documentTitle,
    required String storeName,
    required String exchangeRateSummary,
    required List<String> headers,
    required List<PdfReportRow> rows,
    String? summaryFooter,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 1.5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CHAD A.V.S — $storeName',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  documentTitle,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '$exchangeRateSummary | ${DateTime.now().toString().substring(0, 16)}',
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows.map((r) => r.cells).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
          ),
          if (summaryFooter != null) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              summaryFooter,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10.5,
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'توقيع الإصدار: CHAD A.V.S',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }
}
```[span_1](start_span)[span_1](end_span)

---

بعد حفظ **`lib/services.dart`** بالضغط على **Commit changes**، هل ننتقل إلى **الخطوة السادسة: إنشاء الملف الرئيسي والشاشات `lib/main.dart`**؟
