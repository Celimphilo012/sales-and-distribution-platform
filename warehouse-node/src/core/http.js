'use strict';

const { STATUS_CODES } = require('http');
const { HttpError } = require('./errors');

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

/** Ajv options. Unknown properties are rejected (not stripped) per-schema via additionalProperties:false. */
const AJV_OPTIONS = {
  customOptions: {
    allErrors: true,
    coerceTypes: true,
    removeAdditional: false,
    useDefaults: true,
    // Nullable types ('string' | 'null') are how @IsOptional() is expressed.
    allowUnionTypes: true,
    // Lets `multipleOf: 0.01` mean "at most 2 decimal places" without float error (19.99 / 0.01).
    multipleOfPrecision: 6,
  },
};

function installErrorHandling(app, { logger }) {
  app.setNotFoundHandler((request, reply) => {
    reply.code(404).send({
      statusCode: 404,
      error: 'Not Found',
      message: `Cannot ${request.method} ${request.url.split('?')[0]}`,
      path: request.url,
      timestamp: new Date().toISOString(),
    });
  });

  app.setErrorHandler((error, request, reply) => {
    let status = 500;
    let errorName = 'Internal Server Error';
    let message = 'An unexpected error occurred';
    let extra;

    if (error instanceof HttpError) {
      status = error.statusCode;
      errorName = error.error;
      message = error.messageBody;
      extra = error.extra;
    } else if (error.validation) {
      status = 400;
      errorName = 'Bad Request';
      // A malformed :id path param keeps the original ParseUUIDPipe wording.
      const badUuidParam =
        error.validationContext === 'params' &&
        error.validation.some((v) => v.keyword === 'format' && v.params?.format === 'uuid');
      message = badUuidParam ? 'Validation failed (uuid is expected)' : validationMessages(error.validation);
    } else if (error.code === 'FST_REQ_FILE_TOO_LARGE') {
      status = 400;
      errorName = 'Bad Request';
      message = 'File is too large.';
    } else if (typeof error.code === 'string' && error.code.startsWith('FST_') && error.code.includes('MULTIPART')) {
      status = 400;
      errorName = 'Bad Request';
      message = `Upload rejected: ${error.message}`;
    } else if (error.statusCode && error.statusCode < 500) {
      status = error.statusCode;
      errorName = STATUS_CODES[status] ?? 'Error';
      message = error.message;
    } else {
      logger.error({ err: error }, 'Unhandled error');
      // Raw Prisma/SQL/driver text must not reach clients in production; the full error is logged above.
      if (process.env.NODE_ENV !== 'production') {
        message = error.message;
        errorName = error.name;
      }
    }

    reply.code(status).send({
      statusCode: status,
      error: errorName,
      message,
      path: request.url,
      timestamp: new Date().toISOString(),
      ...(extra ?? {}),
    });
  });
}

module.exports = { AJV_OPTIONS, installErrorHandling, validationMessages };
