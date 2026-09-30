# Khanya platform onboarding

Khanya supports public business registration with platform approval before a tenant workspace becomes active.

## Production configuration

Set `APP_ENV=production` for the API so the development `/auth/bootstrap` endpoint cannot bypass the approval workflow.

Configure one or more trusted platform administrator email addresses with:

```text
PLATFORM_ADMIN_EMAILS=admin@example.com,operations@example.com
```

The configured addresses are matched against authenticated Khanya user email addresses. Platform administrators are intentionally separate from tenant roles such as `owner` and `admin`; a tenant owner does not receive system-wide access.

The platform administrator dashboard can:

- review pending business account applications;
- approve or reject applications;
- see platform-level tenant counts;
- see daily audited tenant activity summaries; and
- inspect recent audited activity for a specific tenant through the platform API.

## Public onboarding flow

1. A visitor opens the Khanya landing page and selects **Open an account**.
2. The visitor submits business, main branch, owner and login details.
3. `POST /api/v1/auth/signup` creates the tenant, main branch and owner membership in pending/inactive state.
4. The application appears in the system administrator's onboarding queue.
5. Approval activates the tenant, branch and membership. Rejection keeps them inactive and records the rejection reason.
6. Only approved tenants can create a normal authenticated tenant session.

## Platform endpoints

All `/api/v1/platform/*` endpoints require an authenticated user whose email is configured in `PLATFORM_ADMIN_EMAILS`.

Pending onboarding records are surfaced in the administration dashboard as in-app notifications. Email, SMS and push delivery are separate notification channels and are not implied by the onboarding queue.
