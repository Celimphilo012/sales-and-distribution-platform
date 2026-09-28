'use strict';

const { STATUS_CODES } = require('http');
const Ajv = require('ajv');
const { HttpError, badRequest } = require('./errors');

/**
 * Turns Ajv validation errors into class-validator-style messages, so clients
 * that display `message` keep seeing the same kind of text the Nest API produced.
 */
function validationMessages(validation) {
  const messages = [];
  for (const err of validation) {
    const prop = (err.instancePath || '').split('/').filter(Boolean).join('.');
    const label = prop || err.params?.missingProperty || 'value';
    switch (err.keyword) {
      case 'required':
        messages.push(`${err.params.missingProperty} should not be empty`);
        break;
      case 'additionalProperties':
        messages.push(`property ${err.params.additionalProperty} should not exist`);
        break;
      case 'type':
        messages.push(`${label} must be a ${[].concat(err.params.type).join(' or ')}`);
        break;
      case 'format':
        messages.push(`${label} must be a valid ${err.params.format}`);
        break;
      case 'minLength':
        messages.push(`${label} must be longer than or equal to ${err.params.limit} characters`);
        break;
      case 'maxLength':
        messages.push(`${label} must be shorter than or equal to ${err.params.limit} characters`);
        break;
      case 'minimum':
        messages.push(`${label} must not be less than ${err.params.limit}`);
        break;
      case 'maximum':
        messages.push(`${label} must not be greater than ${err.params.limit}`);
        break;
      case 'minItems':
        messages.push(`${label} must contain at least ${err.params.limit} elements`);
        break;
      case 'uniqueItems':
        messages.push(`${label}'s elements must be unique`);
        break;
      case 'enum':
        messages.push(`${label} must be one of the following values: ${err.params.allowedValues.join(', ')}`);
        break;
      default:
        messages.push(`${label} ${err.message}`);
    }
  }
  return messages;
}

/** Unknown properties are rejected (not stripped) per-schema via additionalProperties:false. */
const AJV_OPTIONS = {
  allErrors: true,
  coerceTypes: true,
  removeAdditional: false,
  useDefaults: true,
  // Nullable types ('string' | 'null') are how @IsOptional() is expressed.
  allowUnionTypes: true,
  // Lets `multipleOf: 0.01` mean "at most 2 decimal places" without float error (19.99 / 0.01).
  multipleOfPrecision: 6,
};

const ajv = new Ajv(AJV_OPTIONS);
require('ajv-formats')(ajv);

/**
 * Compiles a JSON schema into fn(data) that validates AND coerces `data` in place, throwing the
 * standard 400 body on failure. `onUuidParam` keeps Nest's ParseUUIDPipe wording for bad :id params.
 */
function compileValidator(schema, { isParams = false } = {}) {
  const validate = ajv.compile(schema);
  return (data) => {
    if (validate(data)) return data;
    const badUuid = isParams && validate.errors.some((e) => e.keyword === 'format' && e.params?.format === 'uuid');
    throw badRequest(badUuid ? 'Validation failed (uuid is expected)' : validationMessages(validate.errors));
  };
}

/** A handler returns this after writing the response itself (a file stream, a download, a 304). */
const HANDLED = Symbol('response already sent');

/**
 * Route registration with the same shape every module used under Fastify:
 *   r.post('/path', { onRequest: [guards...], schema: { params, body, querystring } }, handler)
 *
 * Per request, in order: onRequest guards (auth + permission checks) -> params -> body ->
 * querystring validation -> preHandler guards (one-time codes) -> handler. Auth guards run BEFORE
 * validation, so an unauthenticated caller gets 401, never a 400 that leaks the schema. The handler returns the response body; POST answers 201 unless the
 * handler calls res.status() (Nest's default — login/refresh/logout etc. set 200).
 */
function createRoutes(router) {
  function register(method, path, opts, handler) {
    const guards = opts.onRequest ?? [];
    const preHandlers = opts.preHandler ?? [];
    const schema = opts.schema ?? {};
    const checkParams = schema.params && compileValidator(schema.params, { isParams: true });
    const checkBody = schema.body && compileValidator(schema.body);
    const checkQuery = schema.querystring && compileValidator(schema.querystring);

    router[method](path, async (req, res) => {
      // Kept for the audit hook: the route's own params (most specific last), before any coercion.
      req.auditParams = req.params;

      for (const guard of guards) await guard(req, res);

      if (checkParams) checkParams(req.params);
      if (checkBody) {
        const body = req.body ?? {};
        checkBody(body);
        req.body = body;
      }
      if (checkQuery) {
        // Express 5 exposes req.query as a getter; shadow it with the validated, coerced copy.
        const query = { ...req.query };
        checkQuery(query);
        Object.defineProperty(req, 'query', { value: query, writable: true, configurable: true, enumerable: true });
      }

      // Checks that must see the VALIDATED (coerced) request — e.g. one-time-code guards whose
      // `when` inspects the body: `isActive: "false"` has become `false` by now.
      for (const guard of preHandlers) await guard(req, res);

      res.status(method === 'post' ? 201 : 200);
      const result = await handler(req, res);
      if (result === HANDLED || res.headersSent) return;

      if (result && typeof result === 'object' && !Array.isArray(result)) req.responseId = result.id ?? null;
      res.json(result);
    });
  }

  /** Returns get/post/put/patch/delete registrars that prepend `prefix` to every path. */
  function scope(prefix) {
    const join = (path) => (path === '/' ? prefix || '/' : `${prefix}${path}`);
    const make = (method) => (path, opts, handler) =>
      handler === undefined ? register(method, join(path), {}, opts) : register(method, join(path), opts, handler);
    return { get: make('get'), post: make('post'), put: make('put'), patch: make('patch'), delete: make('delete') };
  }

  return { scope };
}

function errorBody(req, status, error, message, extra) {
  return {
    statusCode: status,
    error,
    message,
    path: req.originalUrl,
    timestamp: new Date().toISOString(),
    ...(extra ?? {}),
  };
}

function notFoundHandler(req, res) {
  res.status(404).json(errorBody(req, 404, 'Not Found', `Cannot ${req.method} ${req.originalUrl.split('?')[0]}`));
}

function createErrorHandler(logger) {
  // Express recognises an error handler by its four-parameter signature, so `_next` must stay.
  // eslint-disable-next-line no-unused-vars
  return function errorHandler(error, req, res, _next) {
    let status = 500;
    let errorName = 'Internal Server Error';
    let message = 'An unexpected error occurred';
    let extra;

    if (error instanceof HttpError) {
      status = error.statusCode;
      errorName = error.error;
      message = error.messageBody;
      extra = error.extra;
    } else if (error.name === 'MulterError') {
      status = 400;
      errorName = 'Bad Request';
      if (error.code === 'LIMIT_FILE_SIZE') message = 'File is too large.';
      else if (error.code === 'LIMIT_UNEXPECTED_FILE') message = `Upload rejected: Unexpected field "${error.field}"`;
      else message = `Upload rejected: ${error.message}`;
    } else if ((error.status ?? error.statusCode) < 500) {
      // body-parser errors (malformed JSON, oversized body) carry their own 4xx status.
      status = error.status ?? error.statusCode;
      errorName = STATUS_CODES[status] ?? 'Error';
      message = error.message;
    } else {
      logger.error('Unhandled error', error);
      // Raw SQL/driver text must not reach clients in production; the full error is logged above.
      if (process.env.NODE_ENV !== 'production') {
        message = error.message;
        errorName = error.name;
      }
    }

    if (res.headersSent) return res.end();
    res.status(status).json(errorBody(req, status, errorName, message, extra));
  };
}

module.exports = {
  AJV_OPTIONS,
  HANDLED,
  compileValidator,
  createRoutes,
  createErrorHandler,
  notFoundHandler,
  validationMessages,
};
