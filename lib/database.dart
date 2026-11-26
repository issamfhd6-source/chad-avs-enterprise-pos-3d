import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ============================================================================
// 1. EXCHANGE RATE CONTROLLER & ROLE PERMISSIONS GUARD (CHAD A.V.S)
// ============================================================================

enum UserRole {
  manager,
  branchManager,
  cashier,
}

enum SystemPermission {
  editExchangeRate,
  manageBranchesAndStaff,
  manageInventory,
  createInvoices,
  manageCashboxAndExpenses,
  viewReportsAndExportPdf,
  manageBackupAndSync,
}

class ExchangeRateController extends ChangeNotifier {
  double _usdToNewSyp;
  double _oldToNewSypRatio;
  UserRole _currentRole;
  bool _isDarkMode;

  ExchangeRateController({
    double initialUsdToNewSyp = 135.0,
    double oldToNewSypRatio = 100.0,
    UserRole initialRole = UserRole.manager,
    bool isDarkMode = true,
  })  : _usdToNewSyp = initialUsdToNewSyp,
        _oldToNewSypRatio = oldToNewSypRatio,
        _currentRole = initialRole,
        _isDarkMode = isDarkMode;

  double get usdToNewSyp => _usdToNewSyp;
  double get oldToNewSypRatio => _oldToNewSypRatio;
  UserRole get currentRole => _currentRole;
  bool get isDarkMode => _isDarkMode;

  bool get canEditExchangeRate => _currentRole == UserRole.manager;

  double usdToNewSypValue(double usd) => usd * _usdToNewSyp;
  double usdToOldSypValue(double usd) => usd * _usdToNewSyp * _oldToNewSypRatio;

  double newSypToUsdValue(double newSyp) =>
      _usdToNewSyp <= 0 ? 0 : newSyp / _usdToNewSyp;

  double oldSypToUsdValue(double oldSyp) {
    final denom = _usdToNewSyp * _oldToNewSypRatio;
    return denom <= 0 ? 0 : oldSyp / denom;
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setRole(UserRole role) {
    if (_currentRole == role) return;
    _currentRole = role;
    notifyListeners();
  }

  bool updateUsdRate(double newRate) {
    if (!canEditExchangeRate) return false;
    if (newRate <= 0 || newRate.isNaN || newRate.isInfinite) return false;
    _usdToNewSyp = newRate;
    notifyListeners();
    return true;
  }

  void updateOldToNewRatio(double ratio) {
    if (!canEditExchangeRate) return;
    if (ratio <= 0 || ratio.isNaN || ratio.isInfinite) return;
    _oldToNewSypRatio = ratio;
    notifyListeners();
  }
}

class RolePermissionsGuard {
  final ExchangeRateController rateController;

  RolePermissionsGuard({required this.rateController});

  bool hasPermission(SystemPermission permission) {
    switch (rateController.currentRole) {
      case UserRole.manager:
        return true;
      case UserRole.branchManager:
        return permission == SystemPermission.manageInventory ||
            permission == SystemPermission.createInvoices ||
            permission == SystemPermission.viewReportsAndExportPdf;
      case UserRole.cashier:
        return permission == SystemPermission.createInvoices;
    }
  }

  bool get canOnlyManagerEditExchangeRate =>
      rateController.currentRole == UserRole.manager;
}

// ============================================================================
// 2. DRIFT LOCAL DATABASE SCHEMA (CHAD A.V.S)
// ============================================================================

class Branches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get locationType => text().withDefault(const Constant('branch'))();
  TextColumn get address => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDate)();
}

class SystemUsers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fullName => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().withLength(min: 5, max: 30)();
  TextColumn get role => text().withDefault(const Constant('manager'))();
  IntColumn get branchId => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get barcode => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('عام'))();
  TextColumn get unitName => text().withDefault(const Constant('قطعة'))();
  IntColumn get branchId => integer().withDefault(const Constant(1))();
  IntColumn get totalQuantity => integer().withDefault(const Constant(0))();
  IntColumn get minStockAlert => integer().withDefault(const Constant(5))();
  RealColumn get costUsd => real().withDefault(const Constant(0.0))();
  RealColumn get saleUsd => real().withDefault(const Constant(0.0))();
  RealColumn get costNewSyp => real().withDefault(const Constant(0.0))();
  RealColumn get saleNewSyp => real().withDefault(const Constant(0.0))();
  RealColumn get costOldSyp => real().withDefault(const Constant(0.0))();
  RealColumn get saleOldSyp => real().withDefault(const Constant(0.0))();
  RealColumn get profitMarginPercent => real().withDefault(const Constant(20.0))();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDate)();
}

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get accountType => text()();
  TextColumn get phone => text().nullable()();
  RealColumn get balanceUsd => real().withDefault(const Constant(0.0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDate)();
}

class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text()();
  TextColumn get invoiceType => text()();
  IntColumn get branchId => integer().withDefault(const Constant(1))();
  IntColumn get accountId => integer().nullable()();
  RealColumn get subtotalUsd => real().withDefault(const Constant(0.0))();
  RealColumn get discountUsd => real().withDefault(const Constant(0.0))();
  RealColumn get totalUsd => real().withDefault(const Constant(0.0))();
  RealColumn get paidUsd => real().withDefault(const Constant(0.0))();
  RealColumn get remainingUsd => real().withDefault(const Constant(0.0))();
  RealColumn get exchangeRateUsed => real().withDefault(const Constant(135.0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDate)();
}

class CashboxTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryType => text()();
  TextColumn get category => text().withDefault(const Constant('عام'))();
  RealColumn get amountUsd => real().withDefault(const Constant(0.0))();
  RealColumn get amountNewSyp => real().withDefault(const Constant(0.0))();
  RealColumn get amountOldSyp => real().withDefault(const Constant(0.0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDate)();
}

class SystemSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get storeName =>
      text().withDefault(const Constant('نظام CHAD A.V.S للمحاسبة ونقاط البيع 3D'))();
  RealColumn get usdToNewSypRate => real().withDefault(const Constant(135.0))();
  RealColumn get oldToNewSypRatio => real().withDefault(const Constant(100.0))();
  BoolColumn get autoAdjustCashboxOnPurchase => boolean().withDefault(const Constant(true))();
  BoolColumn get autoAdjustCashboxOnSale => boolean().withDefault(const Constant(true))();
  BoolColumn get autoAdjustCashboxOnExpense => boolean().withDefault(const Constant(true))();
  DateTimeColumn get serverSyncCursor => dateTime().withDefault(currentDate)();
}

@DriftDatabase(tables: [
  Branches,
  SystemUsers,
  Products,
  Accounts,
  Invoices,
  CashboxTransactions,
  SystemSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'chad_avs_enterprise_pos_3d.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }

  Future<void> ensureInitialSeedData() async {
    final existingSettings = await select(systemSettings).get();
    if (existingSettings.isEmpty) {
      await into(systemSettings).insert(
        SystemSettingsCompanion.insert(
          storeName: const Value('نظام CHAD A.V.S للمحاسبة ونقاط البيع 3D'),
          usdToNewSypRate: const Value(135.0),
          oldToNewSypRatio: const Value(100.0),
        ),
      );
    }

    final existingBranches = await select(branches).get();
    if (existingBranches.isEmpty) {
      await into(branches).insert(
        BranchesCompanion.insert(
          name: 'الفرع الرئيسي - CHAD A.V.S',
          locationType: const Value('branch'),
          address: const Value('المركز'),
          isSynced: const Value(true),
        ),
      );
    }

    final existingUsers = await select(systemUsers).get();
    if (existingUsers.isEmpty) {
      await into(systemUsers).insert(
        SystemUsersCompanion.insert(
          fullName: 'المدير العام - CHAD A.V.S',
          phone: '+963900000001',
          role: const Value('manager'),
          branchId: const Value(1),
          isSynced: const Value(true),
        ),
      );
    }
  }
}
