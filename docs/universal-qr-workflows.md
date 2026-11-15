# Khanya POS — universal QR workflows

## Principle

**One QR format, many resource types, one scanner experience.**

A QR code is a **locator**, not an authentication factor, cash receipt, or an instruction to execute a financial transaction. The scanner parses the QR type, selects the appropriate Khanya POS module and fetches the current resource under the signed-in user's tenant/branch permissions. A scan never changes a financial state by itself.

The initial backend QR contract lives in `services/api/app/services/qr_identity.py`. It is a signed opaque `khanyaqr:v1:` payload containing only a type, tenant ID, optional branch ID, resource ID and expiry. Never embed customer personal details, prices, passwords, tokens or payment provider references in QR codes. Displaying or parsing a code grants no access without normal authorization.

## Proposed scan destinations

| QR kind | Scan destination | Required authorization / next action |
| --- | --- | --- |
| product | POS cart product search; product profile | Resolve catalog by tenant; validate active product, current price, branch stock |
| inventory_item | Inventory item | Require inventory read; quantity adjustment is a separate confirmed action |
| stock_location | Inventory location | Inventory permissions and branch scope |
| stocktake | Open stocktake session | Assigned staff + inventory role; counts are separately entered |
| sale | Sale details | Sales read and tenant/branch scope |
| receipt | Digital receipt preview / share | Require an eligible owner or staff permission; use separately authorized sharing links |
| payment_request | Pending checkout amount/reference | Strict short expiry; server lookup; **no payment confirmation solely on scan** |
| customer | Customer account | Customer permission; do not put identity or phone in QR |
| loyalty | Loyalty membership | Membership lookup and points validation; redemption requires explicit authorization |
| appointment | Appointment details / check-in | Verify appointment belongs to tenant and permitted branch |
| purchase_order | Supplier order details | Procurement permission; receiving is a separate action |
| supplier | Supplier profile | Procurement permission |
| staff | Staff profile / assignment | Short expiry; no automatic login, attendance or privilege assignment |
| device | Device registration screen | Short expiry; admin approval and device challenge required |

## Operational flows

**Product sale:** scan product -> resolve under tenant/branch -> validate current price and stock -> add to cart -> normal checkout.

**Digital receipt:** complete sale in normal backend workflow -> generate QR locator for receipt -> scan -> verify access and retrieve receipt.

**Simulated mobile money:** create sale/payment intent -> show short-lived QR locator -> scan -> display simulated payment instructions -> simulated gateway resolves original operation -> server verifies result -> future atomic sale settlement. A QR or a customer screenshot cannot mark a sale paid. The current mobile-money checkout guard stays enabled until an authorized backend flow is built.

**Inventory:** scan product/location -> display item and stock -> authorized worker records receiving, movement or count -> normal backend validation and audit.

**Loyalty:** scan membership -> lookup tenant-scoped account -> apply rules -> explicit redemption at checkout.

## Offline behavior

Locally cached product and inventory tags can be interpreted while offline, but actual records and permissions must be validated against the locally authorized dataset and reconciled on reconnect. Do not treat offline payment QR scanning as proof of settlement. Staff/device/payment QR tags should always require online backend validation.

## Rollout sequence

1. Shared QR types, signed locator parsing, tests, and explicit tenant/branch checks (first PR)
2. Flutter QR generation, camera/scanner input and one Scan action across POS navigation
3. Product scanning and labels, inventory, sale/receipt lookup
4. Customer/loyalty, appointments, procurement, device/staff task navigation
5. Simulated QR payment request flow, end-to-end tests, and eventual provider adapter integration

## Security and lifecycle

- QR signing keys must be provisioned server-side, be independent of login JWT secrets, and support a documented rotation process before production.
- QR locators must never become direct mutation APIs. A scan only opens a resource or requests the next explicit action.
- Resolving tenant-scoped resources must recheck authorization and branch membership; the signature alone does not establish viewer permissions.
- Financial proof, order completion, stock counts, employee attendance and device pairing all require separately authenticated workflows.
- Lost/reprinted QR tags and resource deletion must be handled by authoritative server lookup. Time-limited codes expire naturally.
- Signed QR format is a foundation; it does not implement camera access, QR image rendering, printing, endpoints or UI by itself.
