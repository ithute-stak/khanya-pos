# Khanya POS

Khanya POS is a multi-tenant, offline-first point-of-sale, inventory, purchasing, expense, bookkeeping, reporting, and tax-readiness platform for small businesses in Lesotho.

Developed by **Ithute** for **Khanya Resources Pty Ltd**.

## Technology

### Client

- Flutter / Dart for Android, tablets, and Windows desktop
- BLoC for explicit event/state flows
- GoRouter for navigation
- Dio for HTTP
- Drift / SQLite for offline-first local persistence
- WebSocket client for realtime invalidation/events
- connectivity_plus as a connectivity signal only; network operations still handle actual failures/timeouts
- Windows builds are packaged as a normal installable desktop application

### Backend

- FastAPI
- PostgreSQL + SQLAlchemy
- Redis for cache, coordination, locks, queues/pub-sub and ephemeral realtime state
- WebSockets for tenant/branch/device notifications
- Alembic migrations

## Repository layout

```text
apps/
  mobile/          Shared Flutter client for phone, tablet, and Windows
services/
  api/             FastAPI backend
docs/              Architecture and ADRs
```

## Local backend

```bash
cp .env.example .env
docker compose up --build
```

The local FastAPI service listens on **port 8009**.

Health endpoints:

- `GET http://127.0.0.1:8009/api/v1/health`
- `GET http://127.0.0.1:8009/api/v1/health/ready`

Initial tenant WebSocket route:

- `WS ws://127.0.0.1:8009/api/v1/ws/tenants/{tenant_id}`

The WebSocket route is foundation-only and must receive authentication/authorization before production use.

## Flutter client

The Flutter client is deliberately event-sensitive. Device/network changes enter BLoC as events and produce immutable states. Business features follow the same pattern: user intent -> event -> use case -> local transaction/outbox -> state -> background sync -> server transaction -> realtime invalidation.

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

The current dependency baseline targets Dart 3.12+ / a compatible current stable Flutter toolchain.

## Windows desktop

Khanya POS can be built as a native Windows x64 application while reusing the same POS, inventory, offline database, authentication, sync, and business rules used by the mobile client.

Local Windows prerequisites:

- Windows 10 or Windows 11 x64
- Current stable Flutter SDK
- Visual Studio 2022 with **Desktop development with C++**
- Inno Setup 6 when creating the installer

From PowerShell in `apps/mobile`:

```powershell
.\tool\windows\bootstrap.ps1
flutter run -d windows
```

To create an installable `KhanyaPOS-Setup.exe`:

```powershell
.\tool\windows\build_installer.ps1 -ApiBaseUrl "https://your-khanya-api.example/api/v1"
```

The installer is written to:

```text
apps/mobile/build/windows/installer/KhanyaPOS-Setup.exe
```

If `KHANYA_API_BASE_URL` is not supplied, Android emulator development defaults to `http://10.0.2.2:8009/api/v1`, while native desktop development defaults to `http://127.0.0.1:8009/api/v1`.

GitHub Actions also runs a Windows build, tests the Flutter client, packages the installer with Inno Setup, and publishes `khanya-pos-windows-installer` as a workflow artifact. A manually dispatched build can provide the API base URL that should be compiled into the installer.

## Architecture rules

See [`docs/architecture.md`](docs/architecture.md). Important rules include strict tenant isolation, idempotent offline commands, transactional accounting, append-oriented auditability, deterministic sync, and responsive phone/tablet/desktop layouts.
