'use strict';

const http = require('http');
const { buildApp } = require('./app');

function start() {
  const app = buildApp();
  const { config, logger } = app.locals;
  const server = http.createServer(app);
  // Behind cPanel/Passenger the app sits behind a proxy; keep-alive matches Node's default LB idle timeout.
  server.keepAliveTimeout = 65_000;

  const shutdown = (signal) => {
    logger.info(`${signal} received, shutting down`);
    server.close(async () => {
      try {
        await app.close();
        process.exit(0);
      } catch (error) {
        logger.error(error);
        process.exit(1);
      }
    });
  };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));

  // Explicit 0.0.0.0: Passenger's socket hand-off can't handle several bound addresses.
  server.listen(config.port, '0.0.0.0', () => {
    logger.info(`Warehouse API (Express) listening on http://localhost:${config.port}`);
  });
}

start();
