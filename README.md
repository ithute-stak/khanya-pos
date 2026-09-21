# Khanya POS

Khanya POS is a multi-tenant, offline-first point-of-sale, inventory, purchasing, expense, bookkeeping, reporting, and tax-readiness platform for small businesses in Lesotho.

Developed by **Ithute** for **Khanya Resources Pty Ltd**.

## Platform direction

- Flutter mobile application with BLoC/Cubit state management
- FastAPI backend
- PostgreSQL as the system of record
- Redis for caching, ephemeral state, queues, locks, and pub/sub
- WebSockets for tenant/branch/device event delivery
- Offline-first local persistence and deterministic sync
- Strict tenant and branch isolation
- Event-sensitive UX for sales, stock, purchases, receipt capture, expenses, customers, accounting, reports, and sync state

The repository is being initialized with a modular monorepo structure so the mobile application and backend can evolve independently while sharing one product lifecycle.
