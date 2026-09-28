'use strict';

/**
 * For the few places that must validate by hand (a route that accepts either JSON or multipart
 * cannot use a declarative body schema). Same Ajv instance and error shape as route validation.
 */
const { compileValidator } = require('./http');

module.exports = { compileValidator };
