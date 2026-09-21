# Khanya POS

Khanya POS is a multi-tenant, offline-first point-of-sale, inventory, purchasing, expense, bookkeeping, reporting, and tax-readiness platform for small businesses in Lesotho.

Developed by **Ithute** for **Khanya Resources Pty Ltd**.

## Technology

### Mobile

- Flutter / Dart
- BLoC for explicit event/state flows
- GoRouter for navigation
- Dio for HTTP
- Drift / SQLite for offline-first local persistence
- WebSocket client for realtime invalidation/events
- connectivity_plus as a connectivity signal only; network operations still handle actual failures/timeouts

### Backend

- FastAPI
- PostgreSQL + SQLAlchemy
- Redis for cache, coordination, locks, queues/pub-sub and ephemeral realtime state
- WebSockets for tenant/branch/device notifications
- Alembic migrations

## Repository layout

```text
apps/
  mobile/          Flutter mobile/tablet application
services/
  api/             FastAPI backend
docs/              Architecture and ADRs
```

## Local backend

```bash
cp .env.example .env
docker compose up --build
```

Health endpoints:

- `GET /api/v1/health`
- `GET /api/v1/health/ready`

Initial tenant WebSocket route:

- `WS /api/v1/ws/tenants/{tenant_id}`

The WebSocket route is foundation-only and must receive authentication/authorization before production use.

## Mobile

The mobile foundation is deliberately event-sensitive. Device/network changes enter BLoC as events and produce immutable states. Business features will follow the same pattern: user intent -> event -> use case -> local transaction/outbox -> state -> background sync -> server transaction -> realtime invalidation.

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

The current dependency baseline targets Dart 3.12+ / a compatible current stable Flutter toolchain.

## Architecture rules

See [`docs/architecture.md`](docs/architecture.md). Important rules include strict tenant isolation, idempotent offline commands, transactional accounting, append-oriented auditability, deterministic sync, and responsive phone/tablet layouts.
