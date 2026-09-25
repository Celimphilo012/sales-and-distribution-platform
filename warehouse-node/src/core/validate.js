'use strict';

const Ajv = require('ajv');
const { badRequest } = require('./errors');
const { AJV_OPTIONS, validationMessages } = require('./http');

// Same options as the Fastify route validator, for the few places that must validate by hand
// (a route that accepts either JSON or multipart cannot use a declarative body schema).
const ajv = new Ajv(AJV_OPTIONS.customOptions);
require('ajv-formats')(ajv);

/**
 * Compiles a JSON schema into fn(data) that validates AND coerces `data` in place (exactly like the
 * route-level validator) and throws the same 400 body shape on failure.
 */
function compileValidator(schema) {
  const validate = ajv.compile(schema);
  return (data) => {
    if (!validate(data)) throw badRequest(validationMessages(validate.errors));
    return data;
  };
}

module.exports = { compileValidator };
