'use strict';

/**
 * Mirrors the Nest exception family the original API threw, so response bodies
 * keep the exact shape API consumers already parse:
 *   { statusCode, error, message, path, timestamp, ...extra }
 * `extra` lets a handler attach structured fields (e.g. shortLines) to the body.
 */
class HttpError extends Error {
  constructor(statusCode, error, message, extra) {
    super(Array.isArray(message) ? message.join('; ') : message);
    this.name = 'HttpError';
    this.statusCode = statusCode;
    this.error = error;
    this.messageBody = message;
    this.extra = extra;
  }
}

const make = (statusCode, error) => (message, extra) => new HttpError(statusCode, error, message ?? error, extra);

module.exports = {
  HttpError,
  badRequest: make(400, 'Bad Request'),
  unauthorized: make(401, 'Unauthorized'),
  forbidden: make(403, 'Forbidden'),
  notFound: make(404, 'Not Found'),
  conflict: make(409, 'Conflict'),
  unprocessable: make(422, 'Unprocessable Entity'),
  serviceUnavailable: make(503, 'Service Unavailable'),
  internal: make(500, 'Internal Server Error'),
};
