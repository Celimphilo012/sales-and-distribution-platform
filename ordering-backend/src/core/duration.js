'use strict';

const UNIT_MS = { s: 1000, m: 60 * 1000, h: 60 * 60 * 1000, d: 24 * 60 * 60 * 1000 };

/**
 * Parses simple durations like "15m", "7d", "30s" into milliseconds.
 * Matches the subset of jsonwebtoken duration syntax the JWT_*_EXPIRES_IN env vars use.
 */
function parseDurationMs(duration) {
  const match = /^(\d+)\s*(s|m|h|d)$/.exec(String(duration).trim());
  if (!match) throw new Error(`Invalid duration string: "${duration}"`);
  return Number(match[1]) * UNIT_MS[match[2]];
}

module.exports = { parseDurationMs };
