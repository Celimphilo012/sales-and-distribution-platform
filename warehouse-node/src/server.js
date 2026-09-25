'use strict';

const { buildApp } = require('./app');

async function start() {
  const app = await buildApp();
  const { port } = app.config;

  const shutdown = async (signal) => {
    app.log.info(`${signal} received, shutting down`);
    try {
      await app.close();
      process.exit(0);
    } catch (error) {
      app.log.error(error);
      process.exit(1);
    }
  };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));

  // Explicit 0.0.0.0: with "localhost" Fastify binds several addresses, which Passenger's socket hand-off can't handle.
  await app.listen({ port, host: '0.0.0.0' });
  app.log.info(`Warehouse API (Fastify) listening on http://localhost:${port}`);
}

start().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(error);
  process.exit(1);
});
