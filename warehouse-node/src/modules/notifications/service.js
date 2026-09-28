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

  /** message: { subject, text (SMS), email (branded HTML content, core/email-template.js) }. */
  async function deliver(users, event, message) {
    for (const user of users) {
      if (!user || user.notifyChannel === 'NONE') continue;
      const channel = user.notifyChannel === 'SMS' && user.phone ? 'SMS' : 'EMAIL';
      await notifier.send({
        userId: user.id,
        event,
        channel,
        to: channel === 'SMS' ? user.phone : user.email,
        subject: `${config.appName}: ${message.subject}`,
        text: message.text,
        email: message.email,
      });
    }
  }

  const fireAndForget = (event, work) => {
    work().catch((error) => logger.warn(`Notification "${event}" could not be prepared: ${error.message}`));
  };

  const bucketLabel = (bucket) => bucket.replace('_', ' ').toLowerCase();
  const signed = (a) => `${a.direction === 'INCREASE' ? '+' : '-'}${a.delta}`;
  const describe = (a) =>
    `${signed(a)} ${bucketLabel(a.bucket)} of ${a.product.sku} ${a.product.name} at ${a.location.name} (${a.location.code})`;
  const adjustmentDetails = (a) => [
    ['Product', `${a.product.name} (${a.product.sku})`],
    ['Location', `${a.location.name} (${a.location.code})`],
    ['Change', `${signed(a)} ${bucketLabel(a.bucket)}`],
    ['Requested by', a.requestedByUser?.fullName],
  ];
  const settingsFootnote = (why) => `${why} Choose email, SMS or no notifications in Settings.`;
  /** An "open in the app" button, when APP_URL is configured (the app uses hash routes). */
  const button = (label, route) => (config.appUrl ? { label, url: `${config.appUrl}/#${route}` } : undefined);

  /** A new adjustment request needs a reviewer: tell everyone who can approve it. */
  function adjustmentRequested(adjustment) {
    fireAndForget('adjustment.requested', async () => {
      const users = await recipients('inventory.adjust.approve', adjustment.location.warehouseId, adjustment.requestedBy);
      const requester = adjustment.requestedByUser.fullName;
      await deliver(users, 'adjustment.requested', {
        subject: `approval needed: ${adjustment.product.name}`,
        text: `Stock adjustment awaiting your approval: ${describe(adjustment)}. Requested by ${requester}. Reason: ${adjustment.reason}.`,
        email: {
          preheader: `${requester} requested ${describe(adjustment)}`,
          eyebrow: 'Approval needed',
          tone: 'warning',
          heading: 'A stock adjustment is waiting for your review',
          paragraphs: [
            `${requester} has asked to change recorded stock. Nothing moves until someone with approval rights accepts it.`,
          ],
          details: adjustmentDetails(adjustment),
          quote: { label: 'Reason given', text: adjustment.reason },
          button: button('Review adjustment', '/stock-adjustments'),
          footnote: settingsFootnote('You are receiving this because you can approve stock adjustments for this warehouse.'),
        },
      });
    });
  }

  /** The requester learns the outcome of their request. */
  function adjustmentReviewed(adjustment) {
    fireAndForget('adjustment.reviewed', async () => {
      const approved = adjustment.status === 'APPROVED';
      const verdict = approved ? 'approved' : 'rejected';
      const reviewer = adjustment.reviewedByUser?.fullName ?? 'a reviewer';
      await deliver([await userById(adjustment.requestedBy)], `adjustment.${verdict}`, {
        subject: `stock adjustment ${verdict}: ${adjustment.product.name}`,
        text:
          `Your stock adjustment (${describe(adjustment)}) was ${verdict} by ${reviewer}.` +
          (adjustment.reviewNote ? ` Note: ${adjustment.reviewNote}` : ''),
        email: {
          preheader: `${reviewer} ${verdict} your adjustment: ${describe(adjustment)}`,
          eyebrow: approved ? 'Approved' : 'Rejected',
          tone: approved ? 'success' : 'danger',
          heading: `Your stock adjustment was ${verdict}`,
          paragraphs: [
            approved
              ? `${reviewer} approved your request and the stock records have been updated.`
              : `${reviewer} rejected your request, so no stock was changed.`,
          ],
          details: [...adjustmentDetails(adjustment).slice(0, 3), ['Reviewed by', reviewer]],
          quote: adjustment.reviewNote ? { label: "Reviewer's note", text: adjustment.reviewNote } : undefined,
          button: button('View adjustments', '/stock-adjustments'),
          footnote: settingsFootnote('You are receiving this because you requested this adjustment.'),
        },
      });
    });
  }

  /** One summary to the approvers when a count produces variances (instead of one message per line). */
  function stockCountSubmitted(count, submitter, varianceCount) {
    if (varianceCount === 0) return;
    fireAndForget('stock_count.submitted', async () => {
      // The submitter may not approve their own count's adjustments, so they are not told to.
      const users = await recipients('inventory.adjust.approve', count.warehouseId, submitter.id);
      const variances = `${varianceCount} variance${varianceCount === 1 ? '' : 's'}`;
      await deliver(users, 'stock_count.submitted', {
        subject: `stock count variances awaiting approval: ${count.location.name}`,
        text:
          `Stock count at ${count.location.name} (${count.location.code}) was submitted by ${submitter.fullName}: ` +
          `${variances} now awaiting approval as stock adjustments.`,
        email: {
          preheader: `${submitter.fullName} submitted a count with ${variances}`,
          eyebrow: 'Approval needed',
          tone: 'warning',
          heading: `A stock count found ${variances}`,
          paragraphs: [
            `${submitter.fullName} submitted a stock count. Each difference between the counted and recorded quantity became a stock adjustment, now waiting for approval.`,
          ],
          details: [
            ['Location', `${count.location.name} (${count.location.code})`],
            ['Counted by', submitter.fullName],
            ['Adjustments to review', String(varianceCount)],
          ],
          button: button('Review adjustments', '/stock-adjustments'),
          footnote: settingsFootnote('You are receiving this because you can approve stock adjustments for this warehouse.'),
        },
      });
    });
  }

  return { adjustmentRequested, adjustmentReviewed, stockCountSubmitted };
}

module.exports = { createNotificationsService };
