// Bootstrap data for a fresh install.
//
// All demo/mock data has been removed — the system now starts empty and is
// populated only with real data, which syncs to the Neon cloud database. The
// sole exception is a single bootstrap owner account so the very first login
// works offline before the device has ever reached the server; thereafter the
// real staff list is the one stored in Neon and pulled down on sync.
import 'package:apex_retail_core/models/models.dart';

/// No demo catalog. Real products are added in-app (or pulled from Neon).
List<Product> defaultProducts() => <Product>[];

/// The agri categories the business operates in. Not demo data — these are the
/// real category taxonomy shown in the inventory and POS filters.
const List<String> initialCategories = [
  'Seeds',
  'Fertilizers',
  'Irrigation',
  'Livestock',
  'Pesticides',
  'Herbicides',
  'Farming Tools',
  'Farmer Organic Solutions',
  'Fungicides',
  'Seedlings and Cuttings',
];

/// Legacy retail categories from the original demo data — kept only so a
/// device upgrading from the old build migrates its category list once.
const List<String> legacyRetailCategories = [
  'Grains & Pasta',
  'Dairy',
  'Canned Goods',
  'Snacks',
  'Personal Care',
  'Beverages',
  'Household',
];

const Map<String, String> legacyCategoryMigration = {
  'Grains & Pasta': 'Seeds',
  'Dairy': 'Livestock',
  'Canned Goods': 'Fertilizers',
  'Snacks': 'Seeds',
  'Personal Care': 'Farmer Organic Solutions',
  'Beverages': 'Irrigation',
  'Household': 'Farming Tools',
};

/// The single bootstrap owner account. Replaces the previous four demo logins.
/// Must match the owner seeded server-side in Neon (OWNER_ID / OWNER_NAME /
/// OWNER_PIN) so the same person can sign in on any device, online or offline.
List<StaffProfile> defaultStaff() => [
      StaffProfile(
          userId: 'TM001',
          name: 'Jude',
          role: UserRole.topManager,
          passcode: '2468'),
    ];

/// No seeded sales — sales history starts empty and grows from real POS activity.
List<Sale> seedSales() => <Sale>[];

/// No seeded stock movements.
List<StockTransaction> seedStockTransactions() => <StockTransaction>[];

/// No seeded audit trail — the log starts empty and records real actions.
List<AuditLog> seedAuditLogs() => <AuditLog>[];
