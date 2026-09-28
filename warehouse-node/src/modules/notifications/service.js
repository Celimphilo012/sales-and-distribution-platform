'use strict';

/**
 * Event notifications for the approval workflow (email or SMS, per each recipient's own
 * notify_channel setting; NONE opts out). Recipients are resolved from PERMISSIONS and warehouse
 * ACCESS, never role names (rule 1): e.g. "users holding inventory.adjust.approve who can access
 * this adjustment's warehouse".
 *
 * Every function here is fire-and-forget: it never throws and callers do not await it, because a
 * notification that fails must never undo or fail the stock action that caused it. Failures are
 * logged and recorded as FAILED rows in `notifications` (core/notifier.js).
 */
function createNotificationsService({ db, notifier, config, logger }) {
  /** Active users with `permissionKey` who may access `warehouseId`, excluding `excludeUserId`. */
  function recipients(permissionKey, warehouseId, excludeUserId) {
    return db.query(
      `SELECT DISTINCT u.id, u.email, u.phone, u.notify_channel AS notifyChannel
         FROM users u
         JOIN user_roles ur ON ur.user_id = u.id
         JOIN role_permissions rp ON rp.role_id = ur.role_id
         JOIN permissions p ON p.id = rp.permission_id AND p.\`key\` = ?
        WHERE u.status = 'ACTIVE'
          AND u.notify_channel <> 'NONE'
          AND u.id <> ?
          AND (
            EXISTS (SELECT 1 FROM user_warehouses uw WHERE uw.user_id = u.id AND uw.warehouse_id = ?)
            OR EXISTS (
              SELECT 1 FROM user_roles ur2
                JOIN role_permissions rp2 ON rp2.role_id = ur2.role_id
                JOIN permissions p2 ON p2.id = rp2.permission_id AND p2.\`key\` = 'warehouse.access.all'
               WHERE ur2.user_id = u.id
            )
          )`,
      [permissionKey, excludeUserId ?? '', warehouseId],
    );
  }

  const userById = (id) =>
    db.one("SELECT id, email, phone, notify_channel AS notifyChannel FROM users WHERE id = ? AND status = 'ACTIVE'", [id]);

  async function deliver(users, event, subject, text) {
    for (const user of users) {
      if (!user || user.notifyChannel === 'NONE') continue;
      const channel = user.notifyChannel === 'SMS' && user.phone ? 'SMS' : 'EMAIL';
      await notifier.send({
        userId: user.id,
        event,
        channel,
        to: channel === 'SMS' ? user.phone : user.email,
        subject: `${config.appName}: ${subject}`,
        text,
      });
    }
  }

  const fireAndForget = (event, work) => {
    work().catch((error) => logger.warn(`Notification "${event}" could not be prepared: ${error.message}`));
  };

  const describe = (a) =>
    `${a.direction === 'INCREASE' ? '+' : '-'}${a.delta} ${a.bucket.replace('_', ' ').toLowerCase()} of ` +
    `${a.product.sku} ${a.product.name} at ${a.location.name} (${a.location.code})`;

  /** A new adjustment request needs a reviewer: tell everyone who can approve it. */
  function adjustmentRequested(adjustment) {
    fireAndForget('adjustment.requested', async () => {
      const users = await recipients('inventory.adjust.approve', adjustment.location.warehouseId, adjustment.requestedBy);
      await deliver(
        users,
        'adjustment.requested',
        'stock adjustment awaiting approval',
        `Stock adjustment awaiting your approval: ${describe(adjustment)}. ` +
          `Requested by ${adjustment.requestedByUser.fullName}. Reason: ${adjustment.reason}.`,
      );
    });
  }

  /** The requester learns the outcome of their request. */
  function adjustmentReviewed(adjustment) {
    fireAndForget('adjustment.reviewed', async () => {
      const verdict = adjustment.status === 'APPROVED' ? 'approved' : 'rejected';
      await deliver(
        [await userById(adjustment.requestedBy)],
        `adjustment.${verdict}`,
        `stock adjustment ${verdict}`,
        `Your stock adjustment (${describe(adjustment)}) was ${verdict} by ${adjustment.reviewedByUser?.fullName ?? 'a reviewer'}.` +
          (adjustment.reviewNote ? ` Note: ${adjustment.reviewNote}` : ''),
      );
    });
  }

  /** One summary to the approvers when a count produces variances (instead of one message per line). */
  function stockCountSubmitted(count, submitter, varianceCount) {
    if (varianceCount === 0) return;
    fireAndForget('stock_count.submitted', async () => {
      // The submitter may not approve their own count's adjustments, so they are not told to.
      const users = await recipients('inventory.adjust.approve', count.warehouseId, submitter.id);
      await deliver(
        users,
        'stock_count.submitted',
        'stock count variances awaiting approval',
        `Stock count at ${count.location.name} (${count.location.code}) was submitted by ${submitter.fullName}: ` +
          `${varianceCount} variance${varianceCount === 1 ? '' : 's'} now awaiting approval as stock adjustments.`,
      );
    });
  }

  return { adjustmentRequested, adjustmentReviewed, stockCountSubmitted };
}

module.exports = { createNotificationsService };
