'use strict';

const { badRequest } = require('../core/errors');
const { cols, nest } = require('../core/models');
const { obj, uuid, arrayOf, uuidParams } = require('../core/schema');

/**
 * The LOCAL half of sale-campaign eligibility (ARCHITECTURE.md: campaigns themselves live in the
 * warehouse, which has no concept of a customer — see warehouse-node/src/modules/sales/service.js).
 * For a RESTRICTED campaign, eligibility is assigned by CONSULTANT, not by individual customer: a
 * manager picks which consultants' books of customers may buy at the campaign's price, and every
 * customer whose `assigned_consultant_id` (customers table) points at an eligible consultant
 * qualifies. `orders.js`'s `buildLineInputs()` is the only reader of `isEligible` (one query per
 * RESTRICTED line, at save time).
 */
function createSalesEligibilityService({ db, models }) {
  async function listEligible(campaignId) {
    const rows = await db.query(
      `SELECT ${cols('saleCampaignEligibleConsultant', 'e')}, ${cols('user', 'u', ['id', 'fullName', 'email'], 'consultant.')}
         FROM sale_campaign_eligible_consultants e
         JOIN users u ON u.id = e.consultant_id
        WHERE e.sale_campaign_id = ?
        ORDER BY u.full_name ASC`,
      [campaignId],
    );
    return rows.map(nest);
  }

  /** Replaces the full eligible-consultant list for a campaign — same "provided = replace the full set" semantics as a product's attributes. */
  async function setEligible(campaignId, consultantIds) {
    const unique = [...new Set(consultantIds)];
    if (unique.length) {
      const found = await db.query('SELECT id FROM users WHERE id IN (?)', [unique]);
      if (found.length !== unique.length) {
        const known = new Set(found.map((u) => u.id));
        throw badRequest(`User ${unique.find((id) => !known.has(id))} does not exist`);
      }
    }
    await db.transaction(async (tx) => {
      if (unique.length) {
        await db.exec(
          'DELETE FROM sale_campaign_eligible_consultants WHERE sale_campaign_id = ? AND consultant_id NOT IN (?)',
          [campaignId, unique],
          tx,
        );
      } else {
        await db.exec('DELETE FROM sale_campaign_eligible_consultants WHERE sale_campaign_id = ?', [campaignId], tx);
      }
      const existing = new Set(
        (
          await db.query('SELECT consultant_id AS consultantId FROM sale_campaign_eligible_consultants WHERE sale_campaign_id = ?', [campaignId], tx)
        ).map((r) => r.consultantId),
      );
      const toAdd = unique.filter((id) => !existing.has(id));
      await models.insertMany('saleCampaignEligibleConsultant', toAdd.map((consultantId) => ({ saleCampaignId: campaignId, consultantId })), tx);
    });
    return listEligible(campaignId);
  }

  /** A customer with no assigned consultant is never eligible for a RESTRICTED campaign — fails closed. */
  async function isEligible(campaignId, customerId) {
    const row = await db.one(
      `SELECT 1 AS found
         FROM customers c
         JOIN sale_campaign_eligible_consultants e ON e.consultant_id = c.assigned_consultant_id
        WHERE c.id = ? AND e.sale_campaign_id = ?`,
      [customerId, campaignId],
    );
    return Boolean(row);
  }

  return { listEligible, setEligible, isEligible };
}

const campaignParams = { params: uuidParams('campaignId') };

function salesEligibilityRoutes(app) {
  const { salesEligibility, warehouseApi } = app.services;
  const view = [app.authenticate, app.requirePermissions('sales.view')];
  const manage = [app.authenticate, app.requirePermissions('sales.eligibility.manage')];

  // Relay of the warehouse's campaign list (name, products, discount/eligibility terms) — for the
  // eligibility-picker screen to choose a campaign by name. Same shape as GET /catalogue.
  app.get('/', { onRequest: view }, async () => warehouseApi.getSales());

  app.get('/:campaignId/eligible-consultants', { onRequest: view, schema: campaignParams }, async (request) =>
    salesEligibility.listEligible(request.params.campaignId),
  );

  app.put(
    '/:campaignId/eligible-consultants',
    { onRequest: manage, schema: { ...campaignParams, body: obj({ consultantIds: arrayOf(uuid) }, ['consultantIds']) } },
    async (request) => {
      request.auditEntity = 'sale_campaign_eligible_consultants';
      request.auditEntityId = request.params.campaignId;
      return salesEligibility.setEligible(request.params.campaignId, request.body.consultantIds);
    },
  );
}

module.exports = { createSalesEligibilityService, salesEligibilityRoutes };
