'use strict';

const { SaleCampaignStatus, SaleCampaignEligibility, SaleDiscountType } = require('../../core/enums');
const { obj, nonEmpty, str, num, int, uuid, opt, arrayOf, enumOf, dateString, timeString, uuidParams } = require('../../core/schema');

const money = (extra = {}) => num({ multipleOf: 0.01, ...extra });

const productInput = obj(
  {
    productId: uuid,
    discountType: enumOf(SaleDiscountType),
    discountValue: money({ exclusiveMinimum: 0 }),
    minQuantity: opt(num({ multipleOf: 0.001, exclusiveMinimum: 0 })),
  },
  ['productId', 'discountType', 'discountValue'],
);

// Shared by create and edit/reopen (both full-replace the campaign's terms the same way).
const termsFields = {
  name: nonEmpty(),
  description: opt(str()),
  startsAt: dateString,
  endsAt: dateString,
  eligibility: opt(enumOf(SaleCampaignEligibility)),
  dailyWindowStart: opt(timeString),
  dailyWindowEnd: opt(timeString),
  maxUsesPerCustomer: opt(int({ minimum: 1 })),
  products: arrayOf(productInput, { minItems: 1 }),
};
const createBody = obj(termsFields, ['name', 'startsAt', 'endsAt', 'products']);
// PATCH (edit-while-pending) requires the full term set, same as create — it's a replace, not a patch.
const editBody = createBody;
// POST /reopen's body is all-or-nothing: `{}` to just resubmit as-is, or the full term set to
// replace them at the same time — never a partial object (replaceTerms assumes every field present).
const reopenBody = { oneOf: [obj({}, []), createBody] };

const listQuery = obj({ status: enumOf(SaleCampaignStatus) });
const reviewBody = obj({ reviewNote: opt(str()) });
const rejectBody = obj({ reviewNote: nonEmpty() }, ['reviewNote']);
const idParams = { params: uuidParams('id') };

// Mounted at /sales. Two-step: scheduling never makes a campaign live; approval (by a DIFFERENT
// user) is what does — see sales/service.js for why that's a single atomic status UPDATE rather
// than a separate "apply the effect" step like stock adjustments have.
function salesRoutes(app) {
  const { sales, otp } = app.services;
  const { authenticate, requirePermissions } = app;
  const view = [authenticate, requirePermissions('sales.view')];

  app.get('/', { onRequest: view, schema: { querystring: listQuery } }, async (request) => sales.findAll(request.query, request.user.id));

  app.get('/:id', { onRequest: view, schema: idParams }, async (request) => sales.getAccessible(request.params.id, request.user.id));

  app.post(
    '/',
    { onRequest: [authenticate, requirePermissions('sales.schedule')], schema: { body: createBody } },
    async (request) => {
      const campaign = await sales.createCampaign(request.body, request.user.id);
      request.auditEntity = 'sale_campaigns';
      request.auditEntityId = campaign.id;
      return campaign;
    },
  );

  // Free edit of your own still-PENDING_APPROVAL request — no OTP, same weight as create.
  app.patch(
    '/:id',
    { onRequest: [authenticate, requirePermissions('sales.schedule')], schema: { ...idParams, body: editBody } },
    async (request) => {
      request.auditEntity = 'sale_campaigns';
      request.auditOldValue = await sales.getExisting(request.params.id);
      request.auditAction = 'EDIT';
      return sales.editPending(request.params.id, request.user.id, request.body);
    },
  );

  // Brings a decided campaign back to PENDING_APPROVAL — consequential (pulls a live campaign's
  // effect, or resurrects a stopped one), so it gets the same one-time-code tier as cancel.
  app.post(
    '/:id/reopen',
    {
      onRequest: [authenticate, requirePermissions('sales.schedule')],
      preHandler: [otp.requireOtp('sale_campaign.reopen')],
      schema: { ...idParams, body: reopenBody },
    },
    async (request) => {
      request.auditEntity = 'sale_campaigns';
      request.auditOldValue = await sales.getExisting(request.params.id);
      request.auditAction = 'REOPEN';
      const dto = request.body && Object.keys(request.body).length > 0 ? request.body : undefined;
      return sales.reopen(request.params.id, request.user.id, dto);
    },
  );

  // Approving/rejecting/cancelling is confirmed with a one-time code (catalog/otp-actions.js).
  const review = (action, verb, bodySchema, run) => {
    app.post(
      `/:id/${action}`,
      {
        onRequest: [authenticate, requirePermissions('sales.approve')],
        preHandler: [otp.requireOtp(`sale_campaign.${action}`)],
        schema: { ...idParams, body: bodySchema },
      },
      async (request) => {
        request.auditEntity = 'sale_campaigns';
        request.auditOldValue = await sales.getExisting(request.params.id);
        request.auditAction = verb;
        return run(request);
      },
    );
  };

  review('approve', 'APPROVE', reviewBody, (request) => sales.approve(request.params.id, request.user.id, request.body.reviewNote ?? undefined));
  review('reject', 'REJECT', rejectBody, (request) => sales.reject(request.params.id, request.user.id, request.body.reviewNote));
  review('cancel', 'CANCEL', reviewBody, (request) => sales.cancel(request.params.id, request.user.id, request.body.reviewNote ?? undefined));
}

module.exports = salesRoutes;
