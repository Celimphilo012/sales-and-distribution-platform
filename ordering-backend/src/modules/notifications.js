'use strict';

/**
 * Event notifications for the order workflow (email or SMS, per each recipient's own notify_channel
 * setting; NONE opts out). Recipients are resolved from PERMISSIONS, never role names (rule 1):
 * "users holding orders.approve" hear about submitted orders; an order's consultant hears what
 * happened to it.
 *
 * Every function here is fire-and-forget: it never throws and callers do not await it, because a
 * notification that fails must never undo or fail the order action that caused it. Failures are
 * logged and recorded as FAILED rows in `notifications` (core/notifier.js).
 */
function createNotificationsService({ db, notifier, config, logger }) {
  const USER_COLUMNS = 'u.id, u.email, u.phone, u.full_name AS fullName, u.notify_channel AS notifyChannel';

  /** Active users holding `permissionKey`, except `excludeUserId`. */
  const holdersOf = (permissionKey, excludeUserId) =>
    db.query(
      `SELECT DISTINCT ${USER_COLUMNS}
         FROM users u
         JOIN user_roles ur ON ur.user_id = u.id
         JOIN role_permissions rp ON rp.role_id = ur.role_id
         JOIN permissions p ON p.id = rp.permission_id AND p.\`key\` = ?
        WHERE u.status = 'ACTIVE' AND u.notify_channel <> 'NONE' AND u.id <> ?`,
      [permissionKey, excludeUserId ?? ''],
    );

  const userById = (id) => (id ? db.one(`SELECT ${USER_COLUMNS} FROM users u WHERE u.id = ? AND u.status = 'ACTIVE'`, [id]) : null);

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

  const money = (n) => `E ${Number(n).toFixed(2)}`;
  const nameOf = async (userId) => (await userById(userId))?.fullName ?? 'someone';
  const orderDetails = (order) => [
    ['Order', order.orderNumber],
    ['Customer', order.customer?.name],
    ['Total', money(order.total)],
    ['Lines', String(order.items?.length ?? '')],
  ];
  /** An "open in the app" button, when APP_URL is configured (the app uses hash routes). */
  const button = (label, orderId) => (config.appUrl ? { label, url: `${config.appUrl}/#/orders/${orderId}` } : undefined);
  const footnote = (why) => `${why} Choose email, SMS or no notifications in Settings.`;

  /** A submitted order needs a reviewer: tell everyone who can approve orders. */
  function orderSubmitted(order, submittedBy) {
    fireAndForget('order.submitted', async () => {
      const submitter = await nameOf(submittedBy);
      await deliver(await holdersOf('orders.approve', submittedBy), 'order.submitted', {
        subject: `order ${order.orderNumber} awaiting approval`,
        text: `Order ${order.orderNumber} for ${order.customer.name} (${money(order.total)}) was submitted by ${submitter} and is awaiting your approval.`,
        email: {
          preheader: `${submitter} submitted ${order.orderNumber} for ${order.customer.name}`,
          eyebrow: 'Approval needed',
          tone: 'warning',
          heading: `Order ${order.orderNumber} is waiting for approval`,
          paragraphs: [`${submitter} submitted an order for ${order.customer.name}. It will not be reserved or fulfilled until it is approved.`],
          details: [...orderDetails(order), ['Submitted by', submitter]],
          quote: order.deliveryInfo ? { label: 'Delivery', text: order.deliveryInfo } : undefined,
          button: button('Review order', order.id),
          footnote: footnote('You are receiving this because you can approve orders.'),
        },
      });
    });
  }

  /** What an order's consultant hears about, and how each event reads. */
  const STATUS_EVENTS = {
    APPROVED: { verb: 'approved', tone: 'success', eyebrow: 'Approved', line: 'It will now be reserved and fulfilled.' },
    REJECTED: { verb: 'rejected', tone: 'danger', eyebrow: 'Rejected', line: 'It will not be fulfilled.' },
    CANCELLED: { verb: 'cancelled', tone: 'danger', eyebrow: 'Cancelled', line: 'Any stock held for it has been released.' },
    DISPATCHED: { verb: 'dispatched', tone: 'info', eyebrow: 'Dispatched', line: 'It has left the warehouse.' },
    PARTIALLY_FULFILLED: {
      verb: 'partly dispatched',
      tone: 'warning',
      eyebrow: 'Partly dispatched',
      line: 'Only part of it could be sent — open the order to see which lines are short.',
    },
  };

  /** The order's consultant learns what happened to it (unless they did it themselves). */
  function orderStatusChanged(order, status, changedBy, note) {
    const event = STATUS_EVENTS[status];
    if (!event || !order.consultantId || order.consultantId === changedBy) return;
    fireAndForget(`order.${status.toLowerCase()}`, async () => {
      const actor = await nameOf(changedBy);
      await deliver([await userById(order.consultantId)], `order.${status.toLowerCase()}`, {
        subject: `order ${order.orderNumber} ${event.verb}`,
        text: `Your order ${order.orderNumber} for ${order.customer.name} was ${event.verb} by ${actor}.` + (note ? ` Note: ${note}` : ''),
        email: {
          preheader: `${actor} ${event.verb} ${order.orderNumber} for ${order.customer.name}`,
          eyebrow: event.eyebrow,
          tone: event.tone,
          heading: `Your order ${order.orderNumber} was ${event.verb}`,
          paragraphs: [`${actor} ${event.verb} your order for ${order.customer.name}. ${event.line}`],
          details: [...orderDetails(order), ['By', actor]],
          quote: note ? { label: status === 'REJECTED' ? 'Reason given' : 'Note', text: note } : undefined,
          button: button('View order', order.id),
          footnote: footnote('You are receiving this because this is your order.'),
        },
      });
    });
  }

  /** The consultant hears when their order becomes fully paid. */
  function paymentRecorded({ order, money: summary, recordedBy }) {
    if (summary.paymentStatus !== 'PAID' || !order.consultantId || order.consultantId === recordedBy) return;
    fireAndForget('order.paid', async () => {
      const full = await db.one('SELECT c.name FROM orders o JOIN customers c ON c.id = o.customer_id WHERE o.id = ?', [order.id]);
      await deliver([await userById(order.consultantId)], 'order.paid', {
        subject: `order ${order.orderNumber} fully paid`,
        text: `Order ${order.orderNumber} for ${full?.name ?? 'the customer'} is now fully paid (${money(summary.total)}).`,
        email: {
          preheader: `${order.orderNumber} is fully paid`,
          eyebrow: 'Paid',
          tone: 'success',
          heading: `Order ${order.orderNumber} is fully paid`,
          paragraphs: [`All ${money(summary.total)} for ${full?.name ?? 'this customer'}'s order has now been received.`],
          details: [
            ['Order', order.orderNumber],
            ['Customer', full?.name],
            ['Total paid', money(summary.amountPaid)],
          ],
          button: button('View order', order.id),
          footnote: footnote('You are receiving this because this is your order.'),
        },
      });
    });
  }

  return { orderSubmitted, orderStatusChanged, paymentRecorded };
}

module.exports = { createNotificationsService };
