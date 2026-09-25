/**
 * cPanel / Phusion Passenger entry point.
 *
 * cPanel's "Setup Node.js App" does not run `npm start` — Passenger loads this
 * one file with Node directly. So this file only has to do three things:
 *   1. load .env from the application root (cPanel's own env-var UI also works),
 *   2. require the COMPILED Nest bundle (never src/*.ts — ts-node is not used here),
 *   3. let main.js bootstrap itself; Passenger patches listen(), so the PORT
 *      value is ignored in favour of the socket Passenger hands us.
 *
 * Build before deploying (or run `npm run build` in the cPanel terminal):
 *   npm ci && npx prisma generate && npm run build
 */
require('dotenv').config({ path: require('path').join(__dirname, '.env') });

// `nest build` emits dist/src/main.js here (prisma/seed.ts lifts the rootDir),
// but tolerate dist/main.js in case the build layout changes.
const fs = require('fs');
const path = require('path');

const candidates = [
  path.join(__dirname, 'dist', 'src', 'main.js'),
  path.join(__dirname, 'dist', 'main.js'),
];
const entry = candidates.find((file) => fs.existsSync(file));

if (!entry) {
  throw new Error(
    'Warehouse API is not built. Run `npm run build` in the application root ' +
      `(looked for: ${candidates.join(', ')}).`,
  );
}

require(entry);
