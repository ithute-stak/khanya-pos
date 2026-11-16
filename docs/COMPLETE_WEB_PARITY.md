# Complete Khanya POS web application

Goal: pos.ithute.co.ls must provide the full authenticated Khanya POS experience, not just checkout. Retain the Android and Windows clients.

## Architecture
Extend apps/web against the current FastAPI services and reuse backend-authoritative tenant, stock, accounting, tax, sales and permission rules. A direct Flutter web build is not validated: native dart:io receipt storage, printer adapters, offline database and secure device integrations require web-specific implementations.

## Existing browser features
Business login and branch selection; products and product edits; barcode/SKU and signed QR checkout; cash sales; basic inventory; basic customers; history and receipt printing; QR verification.

## Required feature parity
- Suppliers: list and create introduced in first phase; edit, purchasing links and supplier transactions remain.
- Purchasing: suppliers, purchase orders, receipt of goods, payments and returns.
- POS: till control, held sales, returns/refunds, all supported tenders, discounts and customer credit.
- Inventory: categories, adjustments, transfers, stock take, alerts and detailed audit trail.
- Customers: complete account and transaction workflows.
- Reports: sales, stock, supplier, business health, exports and analytics.
- Accounting, tax, expenses: accounting workflow, tax-readiness, expense documents and reconciliation.
- Staff, business settings, services, workforce, devices and platform administration.
- Documents, QR labels, receipt QR lifecycle, barcode and camera scanning, and browser-specific printing.
- Offline browser persistence and safe synchronization, with conflict recovery and idempotency.

## Release controls
Every module must have authenticated tenant and branch isolation, role checks enforced server-side, safe errors, regression tests and no duplicate financial writes. Printer and camera operations must request permissions and offer browser fallbacks. Do not store tokens in browser localStorage by default.
Deploy immutable tested browser images, preserve the existing backend and database, check HTTPS and health, and verify with authenticated test-tenant workflows.

## Completion criteria
Do not call the web app complete until all Flutter user-facing modules have been mapped, implemented or documented with explicit browser limitations; module-level tests and real-world acceptance checks must pass.