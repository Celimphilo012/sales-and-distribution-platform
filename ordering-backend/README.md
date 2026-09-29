# ordering-backend

The Back-Office / Ordering System API (customers, orders, fulfilment, reports, users/roles) — plain
JavaScript on **Node.js + Express**, **no ORM**: every query is parameterised SQL through `mysql2`.
It replaced the NestJS + Prisma `/backend` (since deleted — it is in git history) with the **same
routes, request/response shapes, permissions and `distribution_platform` schema**; `/ordering-frontend` talks only to it.

Like every part of this platform it follows CLAUDE.md: permissions not roles, the order state machine
in config (`src/modules/order-status-transitions.js`), payment status independent of order status,
backend-enforced security, an audit row on every successful mutation, soft-deleted reference data.
It owns **no inventory**: stock is reserved, released and issued through the warehouse system's
API-key-protected external API (`src/core/warehouse-api.js` — the only code that calls it).

## Run it

```bash
cp .env.example .env    # DATABASE_URL, JWT secrets, WAREHOUSE_API_URL + WAREHOUSE_API_KEY
npm install
mysql -u root -e "CREATE DATABASE distribution_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root distribution_platform < db/schema.sql
npm run seed            # permissions, roles, admin user
npm start               # or: npm run dev  (node --watch)
```

Port 3300 by default. The warehouse API key is issued in the warehouse app (Settings → API keys) with
the scopes `catalogue:read`, `stock:read`, `stock:reserve`, `stock:issue`, `locations:read`.

## Schema changes (no migration tool)

`db/schema.sql` is the whole schema. To change a live database, write the `ALTER`, run it once on each
database, and make the same edit in `schema.sql` in the same commit.

**Upgrading an existing database** (one created before 2026-09-29): back it up, then run
`db/upgrades/2026-09-29-payments-security-notifications.sql` once (see the header in that file). Checked
by upgrading the previous `schema.sql` and diffing it against a fresh load of the current one: identical.

## Reserving stock (automatic, one warehouse, oldest stock first)

`GET /orders/:id/reservation-proposal` (`orders.approve`) plans where an APPROVED order's stock comes
from (`src/modules/stock-allocation.js`): ONE warehouse per order; within it the oldest stock first (the
warehouse's `oldestStockAt`), then fuller locations; a line is split across locations when no single one
holds enough. It returns the chosen warehouse, the alternatives (and whether each could fill the order),
and per line the planned `{ locationId, label, quantity }` plus every location holding the product (for
an override). `?warehouseId=` plans in a specific warehouse.

`POST /orders/:id/reserve` with no `allocations` reserves per the plan (409 with `shortLines` when no
single warehouse can fill the order); with `allocations: [{ orderItemId, locationId, quantity? }]` it
reserves exactly that (every line covered exactly, one warehouse). The warehouse re-checks availability
atomically, so a location without the stock fails the whole reservation and nothing changes. Where each
line is held is stored in `order_item_allocations` (with the location name at the time) and returned on
order reads as `items[].allocations`; dispatch ships the packed quantity from those locations in order.

## Payments

Orders and payments are separate lifecycles (rule 6). `POST /payments` (`payments.record`) records one
payment against an order: `CASH`, `MOBILE_MONEY`, `BANK_TRANSFER` or `CARD` (non-cash needs the provider's
`reference`), optional `paidAt` (never in the future) and `notes`. Rules:

* No payments on `DRAFT`, `REJECTED` or `CANCELLED` orders; the RECORDED total may never exceed the order
  total (overpayment is a 409 carrying `balanceDue`).
* A mistake is never edited or deleted: `POST /payments/:id/void` (`payments.void`, one-time code, reason
  required) marks it `VOIDED`, keeping who/when/why.
* `orders.payment_status` (UNPAID / PARTIAL / PAID) is derived from the recorded payments and rewritten
  in the same transaction as every payment write, under a row lock on the order (no double-paying race).
* An order with payments recorded cannot be cancelled until they are voided.
* `GET /payments?orderId=` — the order's payments + `{ total, amountPaid, balanceDue, paymentStatus }`
  (anyone who can see the order); without `orderId` every payment in a period (`reports.view`). Order
  reads carry `amountPaid`. `GET /reports/payments` — collected by method, voided, and what is still owed.

## One-time codes, MFA, notifications

Ported from `/warehouse-node` (copied — no shared code across systems), same contract:

* **Step-up codes** (428 → `POST /auth/otp` → retry with `X-OTP-Challenge` / `X-OTP-Code`) on order
  approve / reject / cancel, payment void, customer and user deactivation, role delete, MFA off. The list
  is `src/catalog/otp-actions.js`.
* **Sign-in MFA**, optional per user: email / SMS code or an authenticator app (TOTP). Users have
  `phone`, `notify_channel` (EMAIL | SMS | NONE) and `mfa_method`; admins can reset a lost device
  (`POST /users/:id/mfa/reset`).
* **Notifications**: a submitted order goes to everyone holding `orders.approve`; the order's consultant
  hears when it is approved, rejected, cancelled, dispatched (or partly) and when it becomes fully paid.
  Branded HTML emails (`src/core/email-template.js`) + short SMS; set `APP_URL` for "View order" buttons.
* **Delivery settings** are set by an administrator in the app (`settings.manage`; `GET/PUT
  /settings/delivery`, `POST /settings/delivery/test`) — this system's own SMTP / httpSMS settings,
  separate from the warehouse's, stored encrypted in `app_settings`. `.env` is only the fallback.

## Layout

```
app.js                 cPanel/Passenger entry (loads .env, starts src/server)
src/app.js             buildApp(): middleware, services, route table
src/config.js          env -> config
src/core/              db pool, table metadata + SQL helpers, auth guards, audit middleware,
                       error handling + route wrapper, warehouse API client
src/modules/           auth (+MFA), users, roles (+permissions), audit, customers, orders (+catalogue and
                       warehouse-location relays), payments, reports (+dashboard), otp, notifications,
                       delivery-settings
src/catalog/           the permission catalog and default role grants
db/                    schema.sql, seed.js, upgrades/ (one-off SQL for databases older than schema.sql)
test/                  integration suite (fake warehouse, throwaway DB)
```

## Differences from the NestJS `/backend`

* An insufficient-stock reserve (409) keeps the same message **and** now carries structured
  `shortLines` in the body, so clients no longer need to parse the text.
* A reject note of only whitespace is refused (400) — the UI already trimmed it; now the API does too.
* Warehouse calls time out after `WAREHOUSE_API_TIMEOUT_MS` (20 s) as a clean 503 "safe to retry".
* No Swagger UI at `/docs`. `GET /health` is new.

## Testing

```bash
mysql -u root -e "CREATE DATABASE distribution_platform_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root distribution_platform_test < db/schema.sql
DATABASE_URL=mysql://root:@localhost:3306/distribution_platform_test SEED_ADMIN_EMAIL=admin@test.local SEED_ADMIN_PASSWORD='TestPass123!' npm run seed
npm test
```

The suite runs the whole order lifecycle against an in-process fake warehouse (no real stock is
touched). Before the old `/backend` was deleted, a parity script replayed every read endpoint against
both on the same database: 33/33 identical.

## Deploying on cPanel (Phusion Passenger)

Application startup file: `app.js`. No build step. `npm ci --omit=dev` on the server (`argon2` is
native — never upload a Windows-built `node_modules`), set the env vars, restart. Set
`API_BASE_PATH` if the app URL has a path.
