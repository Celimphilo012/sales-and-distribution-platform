'use strict';

const { UserStatus, NotifyChannel } = require('../../core/enums');
const { obj, str, opt, arrayOf, enumOf, uuidParams } = require('../../core/schema');

const roleIds = arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true });
// Loosely shaped here; the service normalises to +E.164 and gives a friendly error.
const phone = opt(str({ maxLength: 32 }));

const createBody = obj(
  {
    email: str({ format: 'email' }),
    password: str({ minLength: 8 }),
    fullName: str(),
    phone,
    notifyChannel: opt(enumOf(NotifyChannel)),
    roleIds: opt(roleIds),
  },
  ['email', 'password', 'fullName'],
);

const updateBody = obj({
  fullName: opt(str()),
  password: opt(str({ minLength: 8 })),
  status: opt(enumOf(UserStatus)),
  phone,
  notifyChannel: opt(enumOf(NotifyChannel)),
  roleIds: opt(roleIds),
});

const profileBody = obj({ fullName: opt(str({ minLength: 1 })), phone, notifyChannel: opt(enumOf(NotifyChannel)) });

const changePasswordBody = obj({ currentPassword: str(), newPassword: str({ minLength: 8 }) }, [
  'currentPassword',
  'newPassword',
]);

const warehousesBody = obj({ warehouseIds: arrayOf({ type: 'string', format: 'uuid' }, { uniqueItems: true }) }, [
  'warehouseIds',
]);

function usersRoutes(app) {
  const { users, access, otp } = app.services;
  const { authenticate, requirePermissions } = app;
  const manage = [authenticate, requirePermissions('users.manage')];
  // Setting a user INACTIVE/SUSPENDED is a deactivation, same as DELETE.
  const deactivating = (req) => req.body.status != null && req.body.status !== 'ACTIVE';

  app.get('/me', { onRequest: [authenticate] }, async (request) => users.findOne(request.user.id));

  // Self-service profile: name, phone number, notification channel.
  app.patch('/me', { onRequest: [authenticate], schema: { body: profileBody } }, async (request) => {
    request.auditEntity = 'users';
    request.auditEntityId = request.user.id;
    return users.updateOwnProfile(request.user.id, request.body);
  });

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

  // The warehouses I am assigned to (holders of warehouse.access.all see every warehouse regardless).
  app.get('/me/warehouses', { onRequest: [authenticate] }, async (request) => access.listForUser(request.user.id));

  app.get('/', { onRequest: manage }, async () => users.findAll());

  app.get('/:id', { onRequest: manage, schema: { params: uuidParams('id') } }, async (request) =>
    users.findOne(request.params.id),
  );

  app.post('/', { onRequest: manage, schema: { body: createBody } }, async (request) => users.create(request.body));

  app.patch(
    '/:id',
    {
      onRequest: manage,
      preHandler: [otp.requireOtp('user.deactivate', { when: deactivating })],
      schema: { params: uuidParams('id'), body: updateBody },
    },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      return users.update(request.params.id, request.body);
    },
  );

  // Full replace of the warehouses a user may access (deny by default — see modules/access).
  app.put(
    '/:id/warehouses',
    {
      onRequest: [authenticate, requirePermissions('warehouse.access.assign')],
      schema: { params: uuidParams('id'), body: warehousesBody },
    },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      request.auditAction = 'ASSIGN_WAREHOUSES';
      return users.setWarehouses(request.params.id, request.body.warehouseIds);
    },
  );

  app.post('/:id/mfa/reset', { onRequest: manage, schema: { params: uuidParams('id') } }, async (request, res) => {
    request.auditOldValue = await users.getExisting(request.params.id);
    request.auditAction = 'MFA_RESET';
    res.status(200);
    return users.resetMfa(request.params.id);
  });

  app.delete(
    '/:id',
    { onRequest: manage, preHandler: [otp.requireOtp('user.deactivate')], schema: { params: uuidParams('id') } },
    async (request) => {
      request.auditOldValue = await users.getExisting(request.params.id);
      request.auditAction = 'DEACTIVATE';
      return users.remove(request.params.id);
    },
  );
}

module.exports = usersRoutes;
