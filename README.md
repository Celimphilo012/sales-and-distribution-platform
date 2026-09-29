# Sales & Distribution Platform

Monorepo for the Inventory, Sales and Distribution Management Platform: **two independent
systems with two separate databases** — the Warehouse System and the Back-Office / Ordering
System — each with its own API, its own auth and its own Flutter front end. See `CLAUDE.md` and
`ARCHITECTURE.md` for the full design and non-negotiable rules; they govern the whole repo.

## Layout

```
sales-and-distribution-platform/
├── CLAUDE.md              Rules and current phase — read first
├── ARCHITECTURE.md        Full system design
├── warehouse-node/        Warehouse API — Node.js + Express + raw SQL (mysql2), port 3200, db warehouse_db
├── warehouse-frontend/    Warehouse Flutter app (talks only to warehouse-node), web port 8090
├── ordering-backend/      Ordering API — Node.js + Express + raw SQL (mysql2), port 3300,
│                          db distribution_platform; calls warehouse-node's API-key API for stock
├── ordering-frontend/     Ordering Flutter app (talks only to ordering-backend), web port 8080
└── edms-prototype-flutter/  UI design prototype the warehouse app's look follows
```

No ORM and no migration tool: each API's `db/schema.sql` is its whole schema. Setup, tests and
deployment steps are in each app's own `README.md`.

## Run locally

```bash
# Warehouse API
cd warehouse-node && npm install && npm start                 # :3200
# Ordering API
cd ordering-backend && npm install && npm start               # :3300
# Front ends
cd warehouse-frontend && flutter run -d web-server --web-port=8090
cd ordering-frontend  && flutter run -d web-server --web-port=8080
```
