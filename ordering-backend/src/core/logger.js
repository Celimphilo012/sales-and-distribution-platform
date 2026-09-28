'use strict';

const LEVELS = { fatal: 60, error: 50, warn: 40, info: 30, debug: 20, silent: Infinity };

/**
 * Minimal leveled console logger (LOG_LEVEL: fatal | error | warn | info | debug | silent).
 * Plain console output is what cPanel/Passenger captures into its log file.
 */
function createLogger(level = process.env.LOG_LEVEL ?? 'info') {
  const threshold = LEVELS[level] ?? LEVELS.info;
  const at = (name, write) => (...args) => {
    if (LEVELS[name] >= threshold) write(`[${new Date().toISOString()}] ${name.toUpperCase()}`, ...args);
  };
  return {
    error: at('error', console.error),
    warn: at('warn', console.warn),
    info: at('info', console.log),
    debug: at('debug', console.log),
  };
}

/** One line per finished request at info level: method, url, status, duration. */
function requestLogger(logger) {
  return (req, res, next) => {
    const started = process.hrtime.bigint();
    res.on('finish', () => {
      const ms = Number(process.hrtime.bigint() - started) / 1e6;
      logger.info(`${req.method} ${req.originalUrl} ${res.statusCode} ${ms.toFixed(1)}ms`);
    });
    next();
  };
}

module.exports = { createLogger, requestLogger };
