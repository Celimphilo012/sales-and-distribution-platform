'use strict';

const { badRequest, conflict, forbidden, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, nest, groupBy, Where } = require('../../core/models');

const CAMPAIGN_SELECT = `
  SELECT ${cols('saleCampaign', 's')},
         ${cols('user', 'ru', ['id', 'fullName', 'email'], 'requestedByUser.')},
         ${cols('user', 'vu', ['id', 'fullName', 'email'], 'reviewedByUser.')}
    FROM sale_campaigns s
    JOIN users ru ON ru.id = s.requested_by
    LEFT JOIN users vu ON vu.id = s.reviewed_by`;

// Rule 7: config, not scattered ifs. Keyed by the CURRENT status -> the statuses it may move to.
// Approve lands on SCHEDULED or ACTIVE depending on whether `starts_at` has already passed; both
// are listed as valid destinations from PENDING_APPROVAL for that reason. Every status but
// PENDING_APPROVAL itself can also go back to PENDING_APPROVAL (edit-while-pending needs no reset;
// everything else does — see reopen()). ACTIVE can also fall back to SCHEDULED: a daily-window
// campaign pausing between today's window and tomorrow's, not ending (see tick()).
const ALLOWED_TRANSITIONS = {
  PENDING_APPROVAL: ['SCHEDULED', 'ACTIVE', 'REJECTED'],
  SCHEDULED: ['ACTIVE', 'CANCELLED', 'PENDING_APPROVAL'],
  ACTIVE: ['ENDED', 'CANCELLED', 'PENDING_APPROVAL', 'SCHEDULED'],
  ENDED: ['PENDING_APPROVAL'],
  REJECTED: ['PENDING_APPROVAL'],
  CANCELLED: ['PENDING_APPROVAL'],
};

/**
 * Sale campaigns: a two-step (request -> approve/reject, separation of duties) workflow over a
 * named, time-windowed, per-product discount — mirrors StockAdjustmentsService exactly. Unlike an
 * adjustment, approval has no separate "real effect" to apply: `status` IS the effect (a product
 * reads as on-sale purely by `sale_campaign_products` joined to an ACTIVE campaign — see
 * ProductsService.attachActiveSale), so approve/reject/cancel are each a single atomic UPDATE.
 * SCHEDULED -> ACTIVE -> ENDED transitions happen OUTSIDE a request, in `scripts/sales-tick.js`
 * (run by a cPanel Cron Job — there is no in-process scheduler here, see README.md).
 */
class SalesService {
  constructor({ db, models, access, notifications }, productsService, cache) {
    this.db = db;
    this.models = models;
    this.access = access;
    this.notifications = notifications;
    this.productsService = productsService;
    this.cache = cache;
  }

  async withProducts(campaigns) {
    if (campaigns.length === 0) return campaigns;
    const rows = await this.db.query(
      `SELECT ${cols('saleCampaignProduct', 'cp')},
              ${cols('product', 'p', ['id', 'sku', 'name', 'sellingPrice'], 'product.')}
         FROM sale_campaign_products cp
         JOIN products p ON p.id = cp.product_id
        WHERE cp.campaign_id IN (?)`,
      [campaigns.map((c) => c.id)],
    );
    const byCampaign = groupBy(rows.map(nest), 'campaignId');
    return campaigns.map((c) => ({ ...c, products: byCampaign.get(c.id) ?? [] }));
  }

  async getExisting(id) {
    const row = await this.db.one(`${CAMPAIGN_SELECT} WHERE s.id = ?`, [id]);
    if (!row) throw notFound(`Sale campaign ${id} not found`);
    const [campaign] = await this.withProducts([nest(row)]);
    return campaign;
  }

  /** Every warehouse this campaign's products belong to — scoping + notification fan-out both need this. */
  warehouseIdsFor(campaign) {
    if (campaign.products.length === 0) return Promise.resolve([]);
    return this.db
      .query(
        `SELECT DISTINCT w.id AS warehouseId
           FROM sale_campaign_products cp
           JOIN products p ON p.id = cp.product_id
           JOIN categories c ON c.id = p.category_id
           JOIN workstreams ws ON ws.id = c.workstream_id
           JOIN warehouses w ON w.id = ws.warehouse_id
          WHERE cp.campaign_id = ?`,
        [campaign.id],
      )
      .then((rows) => rows.map((r) => r.warehouseId));
  }

  /** getExisting + the caller must be able to access at least one warehouse this campaign touches. */
  async getAccessible(id, userId) {
    const campaign = await this.getExisting(id);
    const scope = await this.access.warehouseScope(userId);
    if (scope === null) return campaign;
    const warehouseIds = await this.warehouseIdsFor(campaign);
    if (!warehouseIds.some((w) => scope.includes(w))) {
      throw forbidden('You do not have access to this sale campaign');
    }
    return campaign;
  }

  async findAll(query, viewerId) {
    const scope = await this.access.warehouseScope(viewerId);
    if (scope !== null && scope.length === 0) return [];
    const where = new Where().eq('s.status', query.status);
    if (scope !== null) {
      where.raw(
        `EXISTS (
           SELECT 1 FROM sale_campaign_products cp
             JOIN products p ON p.id = cp.product_id
             JOIN categories c ON c.id = p.category_id
             JOIN workstreams ws ON ws.id = c.workstream_id
            WHERE cp.campaign_id = s.id AND ws.warehouse_id IN (?)
         )`,
        scope,
      );
    }
    const rows = await this.db.query(`${CAMPAIGN_SELECT} ${where.sql} ORDER BY s.requested_at DESC`, where.params);
    return this.withProducts(rows.map(nest));
  }

  /**
   * No window = always "inside". `daily_window_start`/`daily_window_end` are UTC-of-day, same
   * convention as every DATETIME column (`core/db.js`'s `timezone: 'Z'` + session `time_zone
   * '+00:00'`, so CURTIME() is UTC too) — a client picking a LOCAL time must convert to UTC before
   * sending, exactly as it already must for startsAt/endsAt. Mirrors tick()'s own
   * `CURTIME() BETWEEN daily_window_start AND daily_window_end` exactly.
   */
  isInsideDailyWindow(campaign) {
    if (!campaign.dailyWindowStart) return true;
    const now = new Date().toISOString().slice(11, 19);
    return now >= campaign.dailyWindowStart && now <= campaign.dailyWindowEnd;
  }

  /** Both-or-neither, and end after start — the DB CHECK constraints say the same, this just 400s instead of 500ing. */
  assertValidWindow(dto) {
    const { dailyWindowStart, dailyWindowEnd } = dto;
    if (!!dailyWindowStart !== !!dailyWindowEnd) {
      throw badRequest('dailyWindowStart and dailyWindowEnd must both be set, or both left out');
    }
    if (dailyWindowStart && dailyWindowEnd && dailyWindowEnd <= dailyWindowStart) {
      throw badRequest('dailyWindowEnd must be after dailyWindowStart');
    }
  }

  /** Throws unless any PENDING_APPROVAL/SCHEDULED/ACTIVE campaign already carries this product. */
  async assertNoOverlap(productId, excludeCampaignId) {
    const clash = await this.db.one(
      `SELECT s.id, s.name FROM sale_campaign_products cp
         JOIN sale_campaigns s ON s.id = cp.campaign_id
        WHERE cp.product_id = ? AND s.status IN ('PENDING_APPROVAL','SCHEDULED','ACTIVE')
          ${excludeCampaignId ? 'AND s.id <> ?' : ''}`,
      excludeCampaignId ? [productId, excludeCampaignId] : [productId],
    );
    if (clash) throw conflict(`This product is already on the sale campaign "${clash.name}" — only one campaign at a time.`);
  }

  async createCampaign(dto, requestedBy) {
    const startsAt = new Date(dto.startsAt);
    const endsAt = new Date(dto.endsAt);
    if (!(endsAt > startsAt)) throw badRequest('endsAt must be after startsAt');
    this.assertValidWindow(dto);

    const productIds = dto.products.map((p) => p.productId);
    if (new Set(productIds).size !== productIds.length) throw badRequest('Duplicate productId in this campaign');
    await this.productsService.assertAllExist(productIds);
    for (const productId of productIds) await this.assertNoOverlap(productId);

    const campaignId = await this.db.transaction(async (tx) => {
      const campaign = await this.models.insert(
        'saleCampaign',
        {
          name: dto.name,
          description: dto.description,
          startsAt,
          endsAt,
          eligibility: dto.eligibility ?? 'ALL_CUSTOMERS',
          dailyWindowStart: dto.dailyWindowStart ?? null,
          dailyWindowEnd: dto.dailyWindowEnd ?? null,
          maxUsesPerCustomer: dto.maxUsesPerCustomer ?? null,
          requestedBy,
        },
        tx,
      );
      await this.models.insertMany(
        'saleCampaignProduct',
        dto.products.map((p) => ({
          campaignId: campaign.id,
          productId: p.productId,
          discountType: p.discountType,
          discountValue: p.discountValue,
          minQuantity: p.minQuantity ?? 1,
        })),
        tx,
      );
      return campaign.id;
    });

    await this.cache.invalidate(TAGS.SALES);
    const campaign = await this.getExisting(campaignId);
    this.notifications.saleCampaignRequested(campaign, await this.warehouseIdsFor(campaign));
    return campaign;
  }

  async setStatus(id, status, reviewedBy, reviewNote) {
    await this.db.exec(
      'UPDATE sale_campaigns SET status = ?, reviewed_by = ?, reviewed_at = ?, review_note = ?, updated_at = ? WHERE id = ?',
      [status, reviewedBy, new Date(), reviewNote ?? null, new Date(), id],
    );
  }

  /**
   * The ONLY place a sale campaign actually goes live. Lands on ACTIVE rather than SCHEDULED when
   * `starts_at` has already passed by the time it's approved (e.g. a same-day sale) — and, for a
   * daily-window campaign, only when the current time-of-day is also inside today's window (the
   * same check tick() makes; otherwise a same-day approval made outside the window would go live
   * immediately and only self-correct on the next tick).
   */
  async approve(id, reviewedBy, reviewNote) {
    const campaign = await this.getAccessible(id, reviewedBy);
    if (reviewedBy === campaign.requestedBy) {
      throw forbidden('You cannot approve your own sale campaign — a different user must review it');
    }
    const started = new Date(campaign.startsAt) <= new Date();
    const nextStatus = started && this.isInsideDailyWindow(campaign) ? 'ACTIVE' : 'SCHEDULED';
    if (!(ALLOWED_TRANSITIONS[campaign.status] ?? []).includes(nextStatus)) {
      throw conflict(`Sale campaign "${campaign.name}" is ${campaign.status} and cannot be approved`);
    }
    await this.setStatus(id, nextStatus, reviewedBy, reviewNote);
    await this.cache.invalidate(TAGS.SALES, TAGS.CATALOGUE);
    const approved = await this.getExisting(id);
    this.notifications.saleCampaignReviewed(approved, await this.warehouseIdsFor(approved));
    return approved;
  }

  async reject(id, reviewedBy, reviewNote) {
    const campaign = await this.getAccessible(id, reviewedBy);
    if (!(ALLOWED_TRANSITIONS[campaign.status] ?? []).includes('REJECTED')) {
      throw conflict(`Sale campaign "${campaign.name}" is ${campaign.status} and cannot be rejected`);
    }
    await this.setStatus(id, 'REJECTED', reviewedBy, reviewNote);
    await this.cache.invalidate(TAGS.SALES);
    const rejected = await this.getExisting(id);
    this.notifications.saleCampaignReviewed(rejected, await this.warehouseIdsFor(rejected));
    return rejected;
  }

  /** Ends a SCHEDULED or ACTIVE campaign early — same confirmation tier as approve/reject. */
  async cancel(id, cancelledBy, reviewNote) {
    const campaign = await this.getAccessible(id, cancelledBy);
    if (!(ALLOWED_TRANSITIONS[campaign.status] ?? []).includes('CANCELLED')) {
      throw conflict(`Sale campaign "${campaign.name}" is ${campaign.status} and cannot be cancelled`);
    }
    await this.setStatus(id, 'CANCELLED', cancelledBy, reviewNote);
    await this.cache.invalidate(TAGS.SALES, TAGS.CATALOGUE);
    return this.getExisting(id);
  }

  /**
   * Full-replace a campaign's terms (name/description/dates/eligibility/window/products) — shared by
   * editPending (status stays put) and reopen (status also resets to PENDING_APPROVAL). Re-runs
   * every create-time validation, excluding this campaign itself from the overlap check. Must run
   * inside the caller's transaction (`tx`) so the row update and the product-row replace commit or
   * roll back together.
   */
  async replaceTerms(id, dto, tx) {
    const startsAt = new Date(dto.startsAt);
    const endsAt = new Date(dto.endsAt);
    if (!(endsAt > startsAt)) throw badRequest('endsAt must be after startsAt');
    this.assertValidWindow(dto);

    const productIds = dto.products.map((p) => p.productId);
    if (new Set(productIds).size !== productIds.length) throw badRequest('Duplicate productId in this campaign');
    await this.productsService.assertAllExist(productIds);
    for (const productId of productIds) await this.assertNoOverlap(productId, id);

    await this.models.update(
      'saleCampaign',
      id,
      {
        name: dto.name,
        description: dto.description,
        startsAt,
        endsAt,
        eligibility: dto.eligibility ?? 'ALL_CUSTOMERS',
        dailyWindowStart: dto.dailyWindowStart ?? null,
        dailyWindowEnd: dto.dailyWindowEnd ?? null,
        maxUsesPerCustomer: dto.maxUsesPerCustomer ?? null,
      },
      'Sale campaign',
      tx,
    );
    await this.db.exec('DELETE FROM sale_campaign_products WHERE campaign_id = ?', [id], tx);
    await this.models.insertMany(
      'saleCampaignProduct',
      dto.products.map((p) => ({
        campaignId: id,
        productId: p.productId,
        discountType: p.discountType,
        discountValue: p.discountValue,
        minQuantity: p.minQuantity ?? 1,
      })),
      tx,
    );
  }

  /** Free edit of your own still-unreviewed request — nothing's been decided, so status doesn't move. */
  async editPending(id, editedBy, dto) {
    const campaign = await this.getAccessible(id, editedBy);
    if (campaign.status !== 'PENDING_APPROVAL') {
      throw conflict(`Sale campaign "${campaign.name}" is ${campaign.status} — use reopen, not edit`);
    }
    if (editedBy !== campaign.requestedBy) {
      throw forbidden('Only the person who scheduled this campaign can edit it while pending');
    }
    await this.db.transaction((tx) => this.replaceTerms(id, dto, tx));
    await this.cache.invalidate(TAGS.SALES);
    return this.getExisting(id);
  }

  /**
   * Brings a decided campaign (SCHEDULED/ACTIVE/ENDED/REJECTED/CANCELLED) back to PENDING_APPROVAL —
   * always needs a fresh approval by a different user, the same guarantee a first-time approval has.
   * `dto` is optional: given, it replaces the terms at the same time as reopening; omitted, the
   * existing terms are simply resubmitted unchanged. Reopening pulls an ACTIVE campaign's product(s)
   * off sale immediately (status leaves ACTIVE) until it's re-approved.
   */
  async reopen(id, reopenedBy, dto) {
    const campaign = await this.getAccessible(id, reopenedBy);
    if (!(ALLOWED_TRANSITIONS[campaign.status] ?? []).includes('PENDING_APPROVAL')) {
      throw conflict(`Sale campaign "${campaign.name}" is ${campaign.status} and cannot be reopened`);
    }
    await this.db.transaction(async (tx) => {
      if (dto) await this.replaceTerms(id, dto, tx);
      await this.models.update(
        'saleCampaign',
        id,
        { status: 'PENDING_APPROVAL', requestedBy: reopenedBy, requestedAt: new Date(), reviewedBy: null, reviewedAt: null, reviewNote: null },
        'Sale campaign',
        tx,
      );
    });
    await this.cache.invalidate(TAGS.SALES, TAGS.CATALOGUE);
    const reopened = await this.getExisting(id);
    this.notifications.saleCampaignRequested(reopened, await this.warehouseIdsFor(reopened));
    return reopened;
  }

  /**
   * Flips SCHEDULED -> ACTIVE, ACTIVE -> ENDED, and (daily-window campaigns only) ACTIVE back to
   * SCHEDULED for a window that's closed for today but not yet truly finished — the ONLY place any
   * of these transitions happens. Called every minute by the cPanel Cron Job (see README.md), via
   * POST /internal/sales-tick, so it runs inside the live server process and can invalidate that
   * process's in-memory cache immediately (a separate script talking straight to the DB could not —
   * the cache lives in the process that answers real requests).
   */
  async tick() {
    const now = new Date();

    // A plain campaign starts once starts_at passes; a daily-window one only starts inside today's window.
    const starting = await this.db.query(
      `SELECT id, first_activated_at AS firstActivatedAt FROM sale_campaigns
        WHERE status = 'SCHEDULED' AND starts_at <= ?
          AND (daily_window_start IS NULL OR CURTIME() BETWEEN daily_window_start AND daily_window_end)`,
      [now],
    );
    const firstActivations = new Set(starting.filter((r) => !r.firstActivatedAt).map((r) => r.id));

    // True finish — ends_at itself has passed — always wins, daily window or not.
    const ending = await this.db.query("SELECT id FROM sale_campaigns WHERE status = 'ACTIVE' AND ends_at <= ?", [now]);
    const endingIds = new Set(ending.map((r) => r.id));

    // Daily pause — today's window has closed but ends_at hasn't — goes back to SCHEDULED, not
    // ENDED, so it reactivates on its own tomorrow once CURTIME() re-enters the window.
    const pausing = (
      await this.db.query(
        `SELECT id FROM sale_campaigns
          WHERE status = 'ACTIVE' AND ends_at > ? AND daily_window_end IS NOT NULL AND CURTIME() >= daily_window_end`,
        [now],
      )
    ).filter((r) => !endingIds.has(r.id));

    for (const { id } of starting) {
      await this.db.exec(
        "UPDATE sale_campaigns SET status = 'ACTIVE', first_activated_at = COALESCE(first_activated_at, ?), updated_at = ? WHERE id = ?",
        [now, now, id],
      );
    }
    for (const { id } of ending) {
      await this.db.exec("UPDATE sale_campaigns SET status = 'ENDED', updated_at = ? WHERE id = ?", [now, id]);
    }
    for (const { id } of pausing) {
      await this.db.exec("UPDATE sale_campaigns SET status = 'SCHEDULED', updated_at = ? WHERE id = ?", [now, id]);
    }
    if (starting.length || ending.length || pausing.length) await this.cache.invalidate(TAGS.SALES, TAGS.CATALOGUE);

    // Only a TRUE first activation and a TRUE final end get notified — never a daily pause/resume,
    // so a multi-day daily-window campaign doesn't send one started/ended pair per day.
    for (const { id } of starting) {
      if (!firstActivations.has(id)) continue;
      const campaign = await this.getExisting(id);
      this.notifications.saleCampaignStarted(campaign, await this.warehouseIdsFor(campaign));
    }
    for (const { id } of ending) {
      const campaign = await this.getExisting(id);
      this.notifications.saleCampaignEnded(campaign, await this.warehouseIdsFor(campaign));
    }
    return { started: starting.length, ended: ending.length, paused: pausing.length };
  }
}

module.exports = { SalesService };
