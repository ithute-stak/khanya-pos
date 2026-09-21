# Khanya POS Accounting Engine

The accounting engine is an invariant-driven double-entry ledger underneath operational workflows. Business users continue to work in POS, inventory, purchases and expenses; the server posts the accounting effects in the same PostgreSQL transaction.

## Non-negotiable invariants

1. Every posted journal has at least two non-zero lines.
2. Total debits equal total credits to the cent.
3. A journal line has exactly one positive side: debit or credit.
4. Journal accounts belong to the same tenant as the journal entry.
5. Operational source transactions post at most one journal entry.
6. Mobile/client retries use stable operation IDs and cannot duplicate financial effects.
7. Simultaneous duplicate sync attempts are serialized with PostgreSQL transaction advisory locks keyed by tenant, operation scope and client operation ID.
8. Posted journal lines are not edited by application workflows. Corrections use reversal or source-specific correction flows.
9. Automated sale/purchase/expense journals cannot be reversed directly from the accounting API; their source transaction must be corrected instead so subledgers and the GL remain aligned.
10. Inventory unit costs are stored at six-decimal precision; GL money is rounded to two decimals only at posting boundaries.
11. Supporting tax amounts that have not been classified by the tax engine post to Purchase Tax Pending Classification rather than being assumed recoverable.
12. Stock adjustments post corresponding inventory accounting entries.
13. Once an accounting period is locked, new journals dated on or before the lock point are rejected. The lock may only advance, never silently move backward.
14. Operational mutations and their journals are atomic. If accounting posting fails, stock, purchase/payment and other same-transaction effects roll back too.
15. P&L separates sales revenue from other income; adjustment gains do not inflate gross profit.
16. Reconciliation must detect trial-balance, inventory, Stock in Transit, Accounts Payable and supplier-advance differences, and source transactions missing journals.

## Default posting rules

### Sale

- Dr payment account(s)
- Cr Sales Revenue
- Dr Cost of Goods Sold
- Cr Inventory

### Stock purchase

- Dr Inventory for goods received
- Dr Stock in Transit for invoiced stock not yet received
- Dr Non-Stock Purchases for non-stock items
- Dr Purchase Tax Pending Classification for unclassified purchase tax
- Cr immediate payment account(s)
- Cr Accounts Payable for unpaid balance

### Supplier settlement

- Dr Accounts Payable when allocated to a purchase, otherwise Dr Supplier Advances
- Cr payment account

### Expense

- Dr mapped expense account
- Cr payment account

### Inventory adjustment

- Opening balance increase: Dr Inventory / Cr Owner Capital
- Count/correction gain: Dr Inventory / Cr Inventory Adjustment Gains
- Count loss, damage or expiry: Dr Inventory Shrinkage and Adjustments / Cr Inventory

## Correction policy

Manual accountant journals may be reversed by creating an equal-and-opposite journal linked to the original. The original remains intact. Automated source journals are corrected only through their domain workflow (for example refunds/returns), preventing a GL-only correction from silently disagreeing with stock, payments or supplier balances.

## Period close

Accounting settings are tenant-scoped. The current defaults use LSL as base currency and a January fiscal-year start. An authorized accounting user can advance `locked_through` to a past or current instant. It cannot be set in the future and cannot move backward.

Because operational data and its journal are written in one PostgreSQL transaction, a backdated purchase, expense, inventory adjustment or other source event that falls inside a locked period is rejected without leaving partial stock, supplier, payment, outbox or journal state.

## Built-in reconciliation

`GET /accounting/reconciliation` checks:

- trial balance debits versus credits;
- Inventory GL versus current stock valuation;
- Stock in Transit GL versus invoiced stock not yet received;
- Accounts Payable GL versus purchase balances;
- Supplier Advances GL versus unallocated supplier payments;
- completed sales missing sale journals;
- purchases missing purchase journals;
- expenses missing expense journals.

A production close should not proceed while reconciliation reports `healthy: false`.

## Merge gate

The accounting core is not merge-ready unless the exact pull-request head passes PostgreSQL migrations, Alembic model/schema drift checks, backend unit tests, real financial integration tests, concurrent duplicate-operation testing, closed-period rollback testing, Flutter Drift generation, Flutter static analysis and Flutter tests.

Accounting document generation is deliberately a separate layer. Future financial documents should consume this validated ledger rather than implement a second set of accounting calculations.
