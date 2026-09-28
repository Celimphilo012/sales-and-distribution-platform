'use strict';

const mysql = require('mysql2/promise');

/**
 * The one database handle for the process: a mysql2 connection pool plus a few helpers. There is no
 * ORM — every query is plain parameterised SQL (`?` placeholders, never string-concatenated values).
 *
 * Value conventions (the API contract every client already parses):
 *   - DATETIME columns hold UTC. The pool reads and writes them as UTC (`timezone: 'Z'`) and every
 *     session runs with time_zone '+00:00', so NOW()/CURRENT_TIMESTAMP agree with stored values.
 *   - BOOLEAN (TINYINT(1)) comes back as true/false.
 *   - DECIMAL comes back as a string with trailing zeros trimmed ("10.50" -> "10.5", "5.000" -> "5"),
 *     the API's established decimal format.
 *   - JSON columns come back as the raw string (MariaDB stores JSON as LONGTEXT anyway); models.js
 *     parses them, so behaviour is the same on MySQL 8 and MariaDB.
 */

function trimDecimal(text) {
  if (text === null) return null;
  let out = text;
  if (out.includes('.')) out = out.replace(/0+$/, '').replace(/\.$/, '');
  return out === '-0' ? '0' : out;
}

function typeCast(field, next) {
  if (field.type === 'TINY' && field.length === 1) {
    const value = field.string();
    return value === null ? null : value === '1';
  }
  if (field.type === 'NEWDECIMAL' || field.type === 'DECIMAL') return trimDecimal(field.string());
  if (field.type === 'JSON') return field.string();
  return next();
}

/** DATABASE_URL -> mysql2 pool options. `?connection_limit=N` sets the pool size (default 10). */
function poolOptionsFromUrl(databaseUrl) {
  const url = new URL(databaseUrl);
  return {
    host: url.hostname,
    port: url.port ? Number(url.port) : 3306,
    user: decodeURIComponent(url.username),
    password: decodeURIComponent(url.password),
    database: url.pathname.replace(/^\//, ''),
    connectionLimit: Number(url.searchParams.get('connection_limit') ?? 10),
  };
}

function createDb(databaseUrl = process.env.DATABASE_URL) {
  if (!databaseUrl) throw new Error('Missing required env var DATABASE_URL');

  const pool = mysql.createPool({
    ...poolOptionsFromUrl(databaseUrl),
    waitForConnections: true,
    timezone: 'Z',
    dateStrings: false,
    supportBigNumbers: true,
    typeCast,
    charset: 'utf8mb4_unicode_ci',
  });

  // Every new physical connection: UTC session clock (see the header comment).
  pool.pool.on('connection', (connection) => {
    connection.query("SET time_zone = '+00:00'");
  });

  /** Rows for a SELECT. `executor` is the pool or a transaction's connection. */
  async function query(sql, params = [], executor = pool) {
    const [rows] = await executor.query(sql, params);
    return rows;
  }

  async function one(sql, params = [], executor = pool) {
    const rows = await query(sql, params, executor);
    return rows[0];
  }

  /** INSERT/UPDATE/DELETE — returns mysql2's result header ({ affectedRows, insertId, ... }). */
  async function exec(sql, params = [], executor = pool) {
    const [result] = await executor.query(sql, params);
    return result;
  }

  /**
   * Runs fn(connection) inside BEGIN/COMMIT on one dedicated connection; any throw rolls back.
   * Everything that must be atomic passes that connection as the `executor` argument above.
   */
  async function transaction(fn) {
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      const result = await fn(connection);
      await connection.commit();
      return result;
    } catch (error) {
      await connection.rollback().catch(() => {});
      throw error;
    } finally {
      connection.release();
    }
  }

  const close = () => pool.end();

  return { pool, query, one, exec, transaction, close };
}

/** Duplicate key (unique index) violation. */
const isUniqueViolation = (error) => error?.code === 'ER_DUP_ENTRY' || error?.errno === 1062;

module.exports = { createDb, isUniqueViolation, trimDecimal, poolOptionsFromUrl };
