# Sales & Distribution Platform

Monorepo for the Inventory, Sales and Distribution Management Platform — one
backend/API, one central database, two front-end interfaces (Back Office
first, Consultant Portal second). See `CLAUDE.md` and `ARCHITECTURE.md` for
the full design and non-negotiable rules; they govern the whole repo and
stay at this root regardless of which app you're working in.

## Layout

```
sales-and-distribution-platform/
├── CLAUDE.md          Rules and current phase — read first
├── ARCHITECTURE.md    Full system design
├── backend/           NestJS API (TypeScript, MySQL/MariaDB via Prisma)
│                       — see backend/README.md for setup + run steps
└── frontend/           Flutter app (Back Office UI) — not started yet
```

## Backend

The API is complete through Phase 1 (auth, catalogue, warehouses, inventory
ledger, orders + full fulfilment lifecycle, reports/audit/dashboard). Setup,
scripts, and the full endpoint list live in `backend/README.md` — everything
there runs from inside `backend/`:

```bash
cd backend
npm install
npx prisma migrate dev
npm run seed
npm run start:dev
```

## Frontend

Not started. Will be a Flutter app (web/Android/iOS/desktop, Riverpod for
state) living in `frontend/`, reusing one Back Office codebase first and a
Consultant Portal second, per `ARCHITECTURE.md` §K–§L.
