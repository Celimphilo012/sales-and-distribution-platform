'use strict';

/**
 * cPanel / Phusion Passenger entry point ("Application startup file" = app.js).
 *
 * Passenger loads this one file with Node directly — it never runs `npm start`. Plain JavaScript,
 * so there is no build step: upload the folder, `npm ci --omit=dev`, `npx prisma generate`,
 * `npx prisma migrate deploy`, restart. Passenger substitutes its own socket for the port.
 */
require('dotenv').config({ path: require('path').join(__dirname, '.env') });
require('./src/server');
