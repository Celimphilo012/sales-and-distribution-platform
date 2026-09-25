'use strict';

const { UserStatus } = require('@prisma/client');
const { obj, str, nonEmpty, uuid, opt, arrayOf, enumOf, uuidParams } = require('../../core/schema');

const roleIds = arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true });

const createBody = obj(
  {
    email: str({ format: 'email' }),
    password: str({ minLength: 8 }),
    fullName: str(),
    roleIds: opt(roleIds),
  },
  ['email', 'password', 'fullName'],
);

const updateBody = obj({
  fullName: opt(str()),
  password: opt(str({ minLength: 8 })),
  status: opt(enumOf(UserStatus)),
  roleIds: opt(roleIds),
});

const changePasswordBody = obj({ currentPassword: str(), newPassword: str({ minLength: 8 }) }, [
  'currentPassword',
  'newPassword',
]);

async function usersRoutes(app) {
  const { users } = app.services;
  const { authenticate, requirePermissions } = app;
  const manage = [authenticate, requirePermissions('users.manage')];

  app.get('/me', { onRequest: [authenticate] }, async (request) => users.findOne(request.user.id));

  // Self-service: any authenticated user may change their OWN password.
  app.patch(
    '/me/password',
    { onRequest: [authenticate], schema: { body: changePasswordBody } },
    async (request) => {
      request.auditEntity = 'users';
      request.auditEntityId = request.user.id;
      return users.changeOwnPassword(request.user.id, request.body);
    },
  );

  app.get('/', { onRequest: manage }, async () => users.findAll());

  app.get('/:id', { onRequest: manage, schema: { params: uuidParams('id') } }, async (request) =>
    users.findOne(request.params.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) => users.create(request.body));

  app.patch(
    '/:id',
    { onRequest: manage, schema: { params: uuidParams('id'), body: updateBody } },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      return users.update(request.params.id, request.body);
    },
  );

  app.delete('/:id', { onRequest: manage, schema: { params: uuidParams('id') } }, async (request) => {
    request.auditOldValue = await users.getExisting(request.params.id);
    request.auditAction = 'DEACTIVATE';
    return users.remove(request.params.id);
  });
}

module.exports = usersRoutes;
