# Jude Farm Supplies — Flutter POS

An offline-first farm supplies POS + inventory management system for **Jude Farm Supplies**.

## Features (ported 1:1)

- **Role-based login** — Manager / Worker on the POS terminal (Top Manager uses the separate admin app). The terminal always boots locked.
- **POS terminal** — product grid, category filter, SKU "scan" entry, cart with live totals, cash / mobile-money / card payment, change calculation, and a printable thermal receipt.
- **Expired-stock policy** — restrict (supervisor passcode bypass) or allow-and-warn, enforced at checkout.
- **Inventory** — catalog + replenishment ledger, add/edit commodities, restock (with separate-batch handling for differing expiry), quick price adjuster, category manager, and barcode **sticker label printing**.
- **Manager dashboard** — period-scoped revenue / staked / profit / transaction metrics, low-stock & expiry alerts, a sales-velocity line chart, a category-distribution pie chart, a top-commodities leaderboard, and **automatic End-of-Day balancing** with an AI (or rule-based) executive report and owner dispatch.
- **Sales ledger** — searchable transaction history, receipt preview/print, and manager void (restores stock).
- **Audit ledger** — chronological, filterable action trail.
- **Staff settings** — staff directory, role promote/demote, impersonate ("open account"), delete, worker PIN change, printer console, and cloud-sync configuration.
- **Offline-first storage** with a **two-way cloud sync** to the original Express backend when a server URL is configured (Staff Shifts → *Cloud Sync & AI*). Leave the URL blank for single-device offline mode.

Default demo logins: `M001`/`1234` (manager), `W001`/`0000` (worker). Top Manager (`TM001`/`9999`) uses the **apex_retail_admin** app.

## Business features added on top of the original

- **Flexible pricing** — every product has a set **buying cost** and a **minimum selling price (floor)**; the selling price is adjustable at any time, with **no maximum** but never below the floor. Enforced in the add/edit form and the quick-price adjuster.
- **Retail / Wholesale** sale type at data-entry — wholesale items are entered with their own buying/selling prices while stock is managed as one pooled quantity, and carry a *WHOLESALE* badge.
- **Loans & Credit ledger** — register a loan with the borrower's name, contact, amount and **pledged repayment date**; record repayments; the system raises **alerts** (a header bell + due/overdue badges) for loans that are overdue or due within 3 days.
- **Partial payment (Cash + Loan)** at checkout — a customer can pay part in cash and leave the rest on credit. The receipt and toast clearly show **PAID (0 balance)** or the remaining **loan balance**, and a loan is auto-registered against the named customer.
- **Business expenditure recording** — log every cost (rent, utilities, salaries, transport, restocking, taxes…) with amount, description, and who/when; period-filtered totals.
- **Full audit trail** — every action (sales, price changes, loans, payments, expenses, logins, voids, role changes) is stamped with the user and time in the Audit Ledger.
- **Fast data entry** — type the quantity directly (tap the number) instead of only using +/- arrows; numeric keypad fields throughout.
- **Adjustable font size** — `A- / A+` in the header scales the whole UI (80%–160%) for readability and speed.
- **Collapsible sidebar** — the menu (☰) hides the navigation rail so the worker gets a larger, clearer commodity grid; click to show it again.
- **WYSIWYG receipts** — the printed receipt matches the on-screen receipt exactly (same layout, totals, cash/loan breakdown, and barcode), rendered to PDF for the system print dialog or share/export.

## Two installable apps (shared database)

The workspace ships **two independent Flutter projects** plus a shared core package:

| App | Folder | Who | Run |
|-----|--------|-----|-----|
| **Terminal** (POS + manager) | `apex_retail/` | Workers & managers | `cd apex_retail && flutter run` |
| **Top-Admin console** | `apex_retail_admin/` | Owner / Top Manager only | `cd apex_retail_admin && flutter run` |
| **Shared core** | `apex_retail_core/` | (library) | — |

Both apps connect to the same data through the configured sync server. The admin app has its own bundle ID (`com.apexretail.apex_retail_admin`) and is not visible in the terminal login screen.

## Requirements

- Flutter SDK 3.38+ (`flutter doctor`).
- **Windows builds** require a Windows machine with Visual Studio (Desktop C++ workload).
- **Android builds** require the Android SDK + accepted licenses (`flutter doctor --android-licenses`).

## Run in development

```bash
flutter pub get
flutter run -d windows      # Windows desktop
flutter run -d <android-id> # a connected phone/emulator
flutter run -d linux        # Linux desktop (also supported)
```

## Build installers / packages

### Windows (.exe)
```bash
flutter build windows --release
# Output: build\windows\x64\runner\Release\  (ship the whole folder, or wrap it with an
# installer such as Inno Setup / MSIX: `flutter pub add --dev msix` then `dart run msix:create`)
```

### Android (.apk / .aab)
```bash
flutter build apk --release           # sideloadable APK
flutter build appbundle --release     # Play Store bundle
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS (requires macOS + Xcode)
```bash
flutter build ipa --release
```

## Connecting multiple devices (cloud sync)

1. Host the original Express backend (`Apex-Retail-Ledger/apex-retail-ledger`, `npm start`) or any compatible server exposing `/api/sync`, `/api/sales/delete`, `/api/gemini/analyze`.
2. In the app: **Staff Shifts → Cloud Sync & AI → Sync Server URL**, enter e.g. `http://192.168.1.50:3000`, and save.
3. All terminals pointed at the same URL interconnect and reconcile every 12 seconds.

Optionally paste a Gemini API key in the same panel for AI-generated EOD reports (the app falls
back to the built-in rule-based report generator when no key/server is available).

## Project layout

```
apex_retail/                # POS terminal app
  lib/
    main.dart
    screens/                  # login, home shell, pos
apex_retail_admin/            # Super Admin console (separate installable app)
  lib/
    main.dart
    screens/                  # login, admin shell
apex_retail_core/             # shared Dart package
  lib/
    models/models.dart
    data/                     # app_state, sync, seed data
    screens/                  # dashboard, inventory, ledger, audit, staff, loans, expenses
    widgets/receipt_dialog.dart
    utils/                    # formatting + PDF print service
    theme.dart
```
