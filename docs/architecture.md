# Khanya POS architecture

## Product shape

Khanya POS is a multi-tenant, offline-first retail and financial operating system for small businesses in Lesotho. The system must remain usable during poor connectivity and reconcile deterministically when connectivity returns.

## Repository layout

```text
apps/
  mobile/          Flutter application
services/
  api/             FastAPI application and domain services
docs/              Architecture and decision records
```

## Core principles

1. **Tenant isolation first** — every business-owned row carries `tenant_id`; branch-scoped data also carries `branch_id`. Authorization must validate both identity and tenant membership before repository access.
2. **Database as system of record** — PostgreSQL owns durable server state. Redis is never the only copy of financial data.
3. **Offline-first mobile** — Flutter writes user actions to a local transaction/outbox first, renders optimistic state, and synchronizes safely when connectivity is available.
4. **Idempotent commands** — mutating API operations carry a client-generated operation id. Replaying an offline command must not create duplicate sales, purchases, receipts, payments, or ledger postings.
5. **Event-sensitive UX** — UI state is driven by BLoC events and immutable states. Connectivity, sync, WebSocket, scanner, receipt OCR, shift, payment and inventory changes are explicit events.
6. **Transactional accounting** — sale, refund, purchase, expense and payment posting must update operational records and accounting journals in one server-side database transaction.
7. **Realtime is advisory, not authoritative** — WebSockets notify clients that state changed; clients reconcile authoritative state through APIs/local sync.
8. **Auditability** — financial changes are append-oriented and produce audit entries; destructive edits to posted financial documents are avoided in favor of reversals/corrections.

## Backend modules

Planned domain packages:

- identity and access
- tenants and branches
- staff, roles and permissions
- catalog and pricing
- inventory and stock movements
- POS sales, returns and shifts
- customers and credit book
- suppliers and purchasing
- receipt/document capture
- expenses
- payments and banking
- accounting and ledgers
- tax/readiness configuration
- reports and exports
- sync and idempotency
- notifications and realtime
- platform administration

## Event flow

```text
Flutter gesture / device signal
  -> BLoC event
  -> use case
  -> local Drift transaction + outbox
  -> state emitted immediately
  -> sync worker
  -> FastAPI command endpoint
  -> PostgreSQL transaction
  -> domain event / outbox
  -> Redis pub/sub
  -> WebSocket notification
  -> affected clients refresh/reconcile
```

## Offline conflict strategy

Financial documents are not last-write-wins. Commands use immutable identifiers and revision metadata. Safe conflicts are merged automatically; sensitive conflicts (price changes, stock counts, posted financial records) become explicit conflict-resolution states in Flutter.

## Responsive mobile UX

The primary app targets phones and tablets. Layouts use width breakpoints rather than device names, support portrait and landscape where appropriate, and keep cashier flows usable with touch, scanner, keyboard and low-connectivity states.
