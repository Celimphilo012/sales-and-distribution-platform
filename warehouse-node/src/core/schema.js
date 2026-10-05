'use strict';

/**
 * Small JSON-Schema builders. They replace the class-validator DTO classes:
 * core/http.js validates with Ajv before the handler runs, and every object schema
 * built with obj() rejects unknown properties (the old ValidationPipe's
 * `forbidNonWhitelisted: true`).
 *
 * Optional properties in the old DTOs used @IsOptional(), which accepts BOTH
 * undefined and null — opt() reproduces that with a nullable type.
 */

const uuid = { type: 'string', format: 'uuid' };
const str = (extra = {}) => ({ type: 'string', ...extra });
const nonEmpty = (extra = {}) => ({ type: 'string', minLength: 1, ...extra });
const int = (extra = {}) => ({ type: 'integer', ...extra });
const num = (extra = {}) => ({ type: 'number', ...extra });
const bool = { type: 'boolean' };
// class-validator's @IsDateString(): an ISO 8601 date or date-time (date-only such as 2026-09-01 is valid).
const dateString = {
  type: 'string',
  pattern: /^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/.source,
};

// A time-of-day, no date — "15:00" or "15:00:00" (a daily recurring window, e.g. sale_campaigns).
const timeString = { type: 'string', pattern: /^\d{2}:\d{2}(:\d{2})?$/.source };

/** Marks a property optional AND nullable (class-validator's @IsOptional()). */
function opt(schema) {
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  const next = { ...schema, type: types.includes('null') ? types : [...types, 'null'] };
  if (schema.enum) next.enum = [...schema.enum, null];
  return next;
}

function obj(properties, required = []) {
  return { type: 'object', properties, required, additionalProperties: false };
}

function arrayOf(items, extra = {}) {
  return { type: 'array', items, ...extra };
}

function enumOf(enumObject) {
  return { type: 'string', enum: Object.values(enumObject) };
}

/** Params schema for a route with one or more UUID path params. */
function uuidParams(...names) {
  const list = names.length ? names : ['id'];
  return obj(Object.fromEntries(list.map((n) => [n, uuid])), list);
}

/** `?includeInactive=true` style flag — coerced from the string form by Ajv. */
const boolQuery = { type: 'boolean' };

module.exports = { uuid, str, nonEmpty, int, num, bool, dateString, timeString, opt, obj, arrayOf, enumOf, uuidParams, boolQuery };
