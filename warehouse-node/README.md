# warehouse-node

Plain-JavaScript port of the `/warehouse` NestJS API on **Node.js + Express**, with **no ORM** —
every query is parameterised SQL through `mysql2`. It is a **drop-in replacement**: same routes, same request/response shapes, same permissions, same `warehouse_db`
schema — both Flutter apps and the ordering back-office work against it unchanged. The original
`/warehouse` is untouched and still works; run either one (never both against one production
database expecting separate caches — see *Caching → multiple processes*).

Everything CLAUDE.md requires still holds: permissions not roles, the inventory ledger written only via
`InventoryService.applyTransaction()` (with the DB trigger as backstop), location-aware buckets,
unlimited-depth location tree, state in config, backend-enforced security, an audit row on every
successful mutation, soft-deleted reference data.

## Run it

```bash
cp .env.example .env          # set DATABASE_URL, JWT secrets, CORS_ORIGINS
npm install
mysql -u root -e "CREATE DATABASE warehouse_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root warehouse_db < db/schema.sql   # the whole schema, incl. the ledger guard triggers
npm run seed                  # permissions, roles, admin user, system API user, back-office API key
npm run seed:demo             # optional: inventory demo data, through the real write paths
npm start                     # or: npm run dev  (node --watch)
```

Default port is 3200 so it can run beside the original on 3100. `/warehouse-frontend` points here by
default (`AppConfig.apiBaseUrl`). Point the back-office at it by changing `WAREHOUSE_API_URL`; nothing
else changes.

## Layout

```
app.js                    cPanel/Passenger entry (loads .env, requires src/server)
src/server.js             listen + graceful shutdown
src/app.js                buildApp(): Express middleware + route table  (tests call this directly)
src/container.js          builds every service once, in dependency order
src/config.js             env -> config
src/core/                 db pool (db.js), table metadata + SQL helpers (models.js), auth guards, audit
                          middleware, error handling + route wrapper (http.js), uploads, cache
src/modules/<name>/       service.js (business logic) + routes.js (HTTP + JSON-Schema validation)
src/catalog/              permission + attribute-type seed catalogs
db/                       schema.sql (the schema), seed.js, seed-inventory-demo.js
test/                     unit + integration tests, plus parity.js and bench.js
```

Cross-module calls go through services (rule 9). `routes.js` files declare their guards with
`onRequest: [authenticate, requirePermissions('key')]` and a JSON-Schema `schema` (validated with Ajv) —
guards run **before** validation, so an unauthenticated caller gets 401, never a 400 that leaks the schema.

### Data access (no ORM)

`core/models.js` lists each table's fields in API order; columns are their snake_case spelling, and
SELECTs alias them back, so rows come out API-shaped. Value conventions:
DATETIMEs are UTC, BOOLEAN columns are `true`/`false`, DECIMALs are trimmed strings (`"10.5"`), JSON
columns are parsed. Inserts generate the UUID and timestamps in Node; `undefined` fields are skipped and
`null` writes NULL. Multi-row writes use `db.transaction(fn)` on one connection. The ledger rules are
unchanged: `InventoryService.applyTransaction()` is the only writer of `inventory_balances`, unlocking
the DB trigger (`@allow_balance_write`) for its own transaction and resetting it before the connection
returns to the pool.

## Access control, one-time codes, MFA and notifications

**Warehouse access is deny-by-default** (`modules/access`). A user sees and acts on a warehouse — its
locations, stock, workstreams, categories, products, reports — only if assigned to it
(`user_warehouses`, set with `PUT /users/:id/warehouses`, permission `warehouse.access.assign`), or if
they hold `warehouse.access.all` (ADMIN). Workstream manager assignments then narrow catalogue
management further and may only be made inside a warehouse the user already has; removing the
warehouse removes them. The external API-key API is system-to-system and unscoped.

**One-time codes (step-up)** confirm sensitive actions — the list is `src/catalog/otp-actions.js`:
adjustment approve/reject, stock-count submit, every deactivation/deletion (including a PATCH that
sets `isActive: false` / `status: INACTIVE`), API-key revoke, role delete, turning MFA off. Without a
code the route answers **428** `{ otpRequired, action, targetId, availableChannels, defaultChannel }`;
the client asks `POST /auth/otp { action, targetId, channel }` for a code (EMAIL, SMS, or TOTP = the
user's authenticator app) and retries with headers `X-OTP-Challenge` + `X-OTP-Code`. Codes are 6
random digits, stored only as an HMAC, single-use, bound to the action AND the target record, valid 10
minutes, locked after 5 wrong tries; requests are rate-limited per user. OTP guards run *after* body
validation (route `preHandler`), so a coerced value like `isActive: "false"` can't slip past them.

**Sign-in MFA** is optional per user (Settings): email code, SMS code, or an authenticator app (RFC 6238
TOTP, implemented on Node's `crypto`; secrets AES-256-GCM encrypted with `SECRETS_ENCRYPTION_KEY`). With it
on, `POST /auth/login` returns `{ mfaRequired, challengeId, channel, destination, availableChannels }`
and no tokens; `POST /auth/mfa/verify { challengeId, code }` finishes. Email/SMS users can switch the
code to the other channel (`/auth/mfa/resend`). Admins reset a lost device with `POST /users/:id/mfa/reset`.

**Notifications** (`modules/notifications`): new adjustment requests go to users holding
`inventory.adjust.approve` who can access that warehouse; the requester hears the outcome; a submitted
stock count sends one summary. Each user picks EMAIL, SMS or NONE (`notify_channel`, Settings). Every
send is logged in `notifications` (codes are never stored there). Transports (`core/notifier.js`): SMTP
via nodemailer, SMS via **httpSMS** (`POST https://api.httpsms.com/v1/messages/send`, `x-api-key`).
Emails are branded HTML in the app's own look (`core/email-template.js`: table layout + inline styles
for email clients, every value HTML-escaped) with a plain-text alternative; SMS stays short plain text.
Set `APP_URL` to give approval emails an "open in the app" button.

**Delivery settings are set by an administrator in the app** (Settings → Email & SMS delivery,
permission `settings.manage`; `GET/PUT /settings/delivery`, `POST /settings/delivery/test`): SMTP host,
port, TLS, user, password and from-address; httpSMS API key and phone number. They are stored in
`app_settings` (password and API key AES-256-GCM encrypted with `SECRETS_ENCRYPTION_KEY`, never returned
by the API), take effect on the next message, and override `.env`, which is only the fallback. Until
real sending is switched on, emails/SMS are printed to the server log.

**Packing** (`GET /packing`, permission `packing.view`): every open order (a reservation the ordering
system made that is not yet dispatched), oldest first, showing only the lines in the viewer's
warehouses — and, for workstream managers, only their workstreams' products. The ordering system sends
a human `label` ("ORD-0012 · Customer") with each reservation.

## Caching

`src/core/cache/` — an in-memory LRU behind a small async `CacheStore` contract
(`get/set/del/invalidateTags/clear`). Swapping in Redis later means implementing that contract in one
file and setting `CACHE_STORE`; no caller changes.

* **Tag-based invalidation.** Every cached value is stored with tags (`stock`, `catalogue`,
  `structure`, `permissions`, `api-keys`, `workstream-scopes`). A write invalidates its tags *after it
  commits*. Reads therefore never serve stale data in the process that made the write.
* **Single-flight.** N concurrent misses for a key run the loader once.
* **No stale write-after-invalidate.** A value that finished loading while its tag was being
  invalidated is returned to its caller but not stored.
* **Kill switch.** `CACHE_ENABLED=false` makes every `wrap()` a plain database read.

What is cached, and what invalidates it:

| Cached | Key tags | Invalidated by |
|---|---|---|
| User's effective permission keys | `permissions` | any role / role-permission / user change |
| Verified API key (by SHA-256 of the key) | `api-keys` | create / revoke |
| Workstream scope of a user | `workstream-scopes` | assign / unassign |
| Warehouses, locations, subtrees | `structure` | any warehouse / location write |
| Workstreams, categories, attribute types | `catalogue` | their own writes |
| Product lists and single products (with `totalOnHand`) | `catalogue`, `stock` | product/image/category writes **and every ledger write** |
| Reports and the dashboard | `stock`, `catalogue`, `structure` | any of the above |
| `/api/v1/catalogue` (external) | via the product/category caches | same |

**Never cached** (correctness beats speed): stock availability, reserve / release / issue, the leaf
check, balances and transactions lists, anything read inside a write, audit logs, `getExisting()`
used for audit old-values. Free-text product search is not cached (unbounded key space).

**Multiple processes.** Invalidation is per process. If you run more than one process against the same
database (cluster/PM2), a change made in process A is seen by B only after the relevant TTL
(`CACHE_*_TTL_MS`). Passenger on cPanel normally runs one process. For strict cross-process
invalidation, implement the Redis store.

## Other optimisations vs the original

* API-key auth: the original verified the key against **every** active key's argon2 hash on **every**
  request. Argon2 stays as the at-rest format; verification now runs once per key per TTL, and
  `last_used_at` is written at most once a minute per key.
* `applyTransaction` and reservation lines use a cheap `assertExists` instead of loading the whole
  product (with its stock aggregate) just to prove it exists; stock counts check all products in one query.
* Audit rows are written on the response's `finish` event, after the client already has its answer.
* Uploaded images are served with `ETag` + `Cache-Control: private, no-cache`, so revalidation is a
  cheap 304.
* gzip via `compression` (large lists compress ~10x), and ETags on JSON.
* Report queries got a deterministic tiebreaker (`ORDER BY … , sku`); the original's order for ties was
  arbitrary.

## Deliberate differences from `/warehouse`

* Validation messages are class-validator-style (`property x should not exist`,
  `email must be a valid email`) but not word-for-word identical for every rule.
  Status codes and the error body shape (`statusCode, error, message, path, timestamp`) are identical.
* A missing upload file is a clean 400 (the original threw a 500).
* Multipart `isPrimary=false` is parsed as false (the original's `Boolean("false")` made it true).
* No Swagger UI at `/docs` (the original had one). It would add several MB of `node_modules` and file
  count, which matters on quota-limited shared hosting; route schemas are already JSON-Schema, so an
  OpenAPI document can be generated from them later if wanted.
* `GET /health` (public, returns `{"status":"ok"}`) is new.

## Testing

```bash
# one-time: a throwaway database (the harness refuses any name that does not end in _test)
mysql -u root -e "CREATE DATABASE warehouse_db_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root warehouse_db_test < db/schema.sql
DATABASE_URL=mysql://root:@localhost:3306/warehouse_db_test SEED_ADMIN_EMAIL=admin@test.local SEED_ADMIN_PASSWORD='TestPass123!' npm run seed

npm test                      # cache unit tests + full API integration suite (real HTTP on a random port)
```

`test/parity.js` replays every read endpoint (and the error shapes) against the original API and this
port on the same database and diffs the results; `test/bench.js` compares throughput.

## Deploying on cPanel (Phusion Passenger)

Application startup file: `app.js`. No build step — it is plain JavaScript.

```bash
source /home/<user>/nodevenv/<app-root>/<node-version>/bin/activate   # cPanel shows this line
npm ci --omit=dev
```

Set the environment variables in cPanel's Node.js app page (or a `.env` in the app root). If the app
URL has a path (e.g. `/api`), set `API_BASE_PATH=api`. Then Restart.

`argon2` is native: install on the server (never upload `node_modules` built on Windows). There is no
generate step and no query-engine binary any more.
