import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:chad_avs_pos_3d/database.dart';

class PricingSyncService {
  final AppDatabase db;
  final ExchangeRateController rateController;
  PricingSyncService({required this.db, required this.rateController});

  Future<bool> updateExchangeRateAndRepriceAllProducts(double newUsdRate) async {
    if (!rateController.canEditExchangeRate) return false;
    if (!rateController.updateUsdRate(newUsdRate)) return false;
    final ratio = rateController.oldToNewSypRatio;

    await db.transaction(() async {
      await db.update(db.systemSettings).write(
            SystemSettingsCompanion(
              usdToNewSypRate: Value(newUsdRate),
              oldToNewSypRatio: Value(ratio),
            ),
          );
      final all = await db.select(db.products).get();
      for (final prod in all) {
        final costNew = prod.costUsd * newUsdRate;
        final saleNew = prod.saleUsd * newUsdRate;
        await (db.update(db.products)..where((t) => t.id.equals(prod.id))).write(
          ProductsCompanion(
            costNewSyp: Value(costNew),
            saleNewSyp: Value(saleNew),
            costOldSyp: Value(costNew * ratio),
            saleOldSyp: Value(saleNew * ratio),
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
  InvoiceService({required this.db, required this.rateController});

  Future<int> createInvoice({
    required String invoiceType,
    required int branchId,
    int? accountId,
    required double subtotalUsd,
    required double discountUsd,
    required double paidUsd,
    String? notes,
  }) async {
    final net = (subtotalUsd - discountUsd).clamp(0.0, double.infinity);
    final rem = (net - paidUsd).clamp(0.0, double.infinity);
    final rate = rateController.usdToNewSyp;
    final ratio = rateController.oldToNewSypRatio;
    final invNo = 'INV-${DateTime.now().millisecondsSinceEpoch}';

    return db.transaction(() async {
      final id = await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              invoiceNumber: invNo,
              invoiceType: invoiceType,
              branchId: Value(branchId),
              accountId: Value(accountId),
              subtotalUsd: Value(subtotalUsd),
              discountUsd: Value(discountUsd),
              totalUsd: Value(net),
              paidUsd: Value(paidUsd),
              remainingUsd: Value(rem),
              exchangeRateUsed: Value(rate),
              notes: Value(notes),
              isSynced: const Value(false),
            ),
          );

      if (accountId != null && rem > 0) {
        final accs = await (db.select(db.accounts)
              ..where((t) => t.id.equals(accountId)))
            .get();
        if (accs.isNotEmpty) {
          final acc = accs.first;
          await (db.update(db.accounts)..where((t) => t.id.equals(acc.id))).write(
            AccountsCompanion(
              balanceUsd: Value(acc.balanceUsd + rem),
              isSynced: const Value(false),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      if (paidUsd > 0) {
        final type = (invoiceType == 'sale' || invoiceType == 'purchaseReturn')
            ? 'deposit'
            : 'withdraw';
        await db.into(db.cashboxTransactions).insert(
              CashboxTransactionsCompanion.insert(
                entryType: type,
                category: Value('فاتورة $invNo'),
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
  CashboxService({required this.db, required this.rateController});

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
  BranchesUsersService({required this.db, required this.rateController});

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
  SyncBackupService({required this.db, required this.rateController});

  Future<int> pushPendingRecords() async {
    int count = 0;
    await db.transaction(() async {
      final pList = await (db.select(db.products)
            ..where((t) => t.isSynced.equals(false)))
          .get();
      count += pList.length;
      await (db.update(db.products)..where((t) => t.isSynced.equals(false)))
          .write(const ProductsCompanion(isSynced: Value(true)));

      final iList = await (db.select(db.invoices)
            ..where((t) => t.isSynced.equals(false)))
          .get();
      count += iList.length;
      await (db.update(db.invoices)..where((t) => t.isSynced.equals(false)))
          .write(const InvoicesCompanion(isSynced: Value(true)));

      final cList = await (db.select(db.cashboxTransactions)
            ..where((t) => t.isSynced.equals(false)))
          .get();
      count += cList.length;
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
    await db.update(db.systemSettings).write(
          SystemSettingsCompanion(
            serverSyncCursor: Value(DateTime.now().subtract(lookback)),
          ),
        );
    await (db.select(db.invoices)
          ..limit(maxRecordsPerTable.clamp(1, 150)))
        .get();
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
  BackupPrintService({required this.db, required this.rateController});

  final Map<String, List>> _store = {};

  Future<CloudBackupSnapshot> createBackupByPhone(String phone) async {
    final key = phone.trim();
    final prods = await db.select(db.products).get();
    final invs = await db.select(db.invoices).get();
    final id = 'CHAD-AVS-BKP-${DateTime.now().millisecondsSinceEpoch}';
    final data = {
      'backupId': id,
      'phone': key,
      'createdAt': DateTime.now().toIso8601String(),
      'usdToNewSypRate': rateController.usdToNewSyp,
      'products': prods
          .map((e) => {
                'id': e.id,
                'name': e.name,
                'qty': e.totalQuantity,
                'saleUsd': e.saleUsd,
              })
          .toList(),
      'invoices': invs
          .map((e) => {
                'id': e.id,
                'number': e.invoiceNumber,
                'totalUsd': e.totalUsd,
              })
          .toList(),
    };
    final dir = await getApplicationDocumentsDirectory();
    await File(p.join(dir.path, '$id.json')).writeAsString(jsonEncode(data));
    _store.putIfAbsent(key, () => []).insert(0, data);
    return CloudBackupSnapshot(
      backupId: id,
      phone: key,
      createdAt: DateTime.now(),
      productsCount: prods.length,
      invoicesCount: invs.length,
    );
  }

  List<CloudBackupSnapshot> listBackupsForPhone(String phone) {
    return (_store[phone.trim()] ?? const [])
        .map((e) => CloudBackupSnapshot(
              backupId: e['backupId'] as String? ?? '',
              phone: e['phone'] as String? ?? phone,
              createdAt: DateTime.tryParse(e['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              productsCount: (e['products'] as List?)?.length ?? 0,
              invoicesCount: (e['invoices'] as List?)?.length ?? 0,
            ))
        .toList();
  }

  bool deleteBackup(String phone, String backupId) {
    final list = _store[phone.trim()];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((e) => e['backupId'] == backupId);
    return list.length < before;
  }

  Future<bool> restoreBackup(String phone, String backupId) async {
    final list = _store[phone.trim()];
    if (list == null) return false;
    final match = list.where((e) => e['backupId'] == backupId).toList();
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
    return [
      'CHAD A.V.S - $storeName',
      'Invoice: $invoiceNumber ($invoiceType)',
      'Total: \$${totalUsd.toStringAsFixed(2)}',
      'New SYP: ${newSyp.toStringAsFixed(1)}',
      'Old SYP: ${(newSyp * ratio).toStringAsFixed(0)}',
      'Paid: \$${paidUsd.toStringAsFixed(2)}',
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
          pw.Text('CHAD A.V.S - $storeName'),
          pw.Text(documentTitle),
          pw.Text(exchangeRateSummary),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows.map((r) => r.cells).toList(),
          ),
          if (summaryFooter != null) ...[
            pw.SizedBox(height: 10),
            pw.Text(summaryFooter),
          ],
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }
}
