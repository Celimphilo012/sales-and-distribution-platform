"use strict";
exports.resolveBucketDeltas = resolveBucketDeltas;
const { InventoryTransactionType } = require('../../core/enums');
const { badRequest } = require('../../core/errors');
/**
 * Maps a transaction type + its location(s) to the concrete balance-bucket
 * deltas it must apply. This is the single place that encodes "what does
 * this transaction type actually do" (rule 7: config, not scattered ifs) —
 * InventoryService.applyTransaction() just executes whatever this returns.
 *
 * There is no dedicated "EXPIRE" transaction type in the §E type list, so
 * the `expired` bucket is corrected via ADJUSTMENT (bucket: 'expired'),
 * the same generic path used for any other manual correction.
 */
function resolveBucketDeltas(input) {
    const { type, quantity, fromLocationId, toLocationId, bucket } = input;
    const requireFrom = () => {
        if (!fromLocationId)
            throw badRequest(`${type} requires fromLocationId`);
    };
    const requireTo = () => {
        if (!toLocationId)
            throw badRequest(`${type} requires toLocationId`);
    };
    const forbidFrom = () => {
        if (fromLocationId)
            throw badRequest(`${type} does not accept fromLocationId`);
    };
    const forbidTo = () => {
        if (toLocationId)
            throw badRequest(`${type} does not accept toLocationId`);
    };
    switch (type) {
        // Stock enters the system at a location.
        case InventoryTransactionType.RECEIVE:
        case InventoryTransactionType.RETURN:
            requireTo();
            forbidFrom();
            return [{ locationId: toLocationId, bucket: 'onHand', delta: quantity }];
        // Stock leaves the system from a location.
        case InventoryTransactionType.ISSUE:
        case InventoryTransactionType.SALE:
            requireFrom();
            forbidTo();
            return [{ locationId: fromLocationId, bucket: 'onHand', delta: -quantity }];
        // Stock physically moves between two locations (§H point 3).
        case InventoryTransactionType.TRANSFER:
            requireFrom();
            requireTo();
            if (fromLocationId === toLocationId) {
                throw badRequest('TRANSFER requires two different locations');
            }
            return [
                { locationId: fromLocationId, bucket: 'onHand', delta: -quantity },
                { locationId: toLocationId, bucket: 'onHand', delta: quantity },
            ];
        // Same-location bucket reclassification: sellable stock leaves on_hand
        // and enters the damaged/lost bucket. Never a silent overwrite (rule 4)
        // — both sides of the move are recorded as explicit deltas.
        case InventoryTransactionType.DAMAGED:
            requireFrom();
            forbidTo();
            return [
                { locationId: fromLocationId, bucket: 'onHand', delta: -quantity },
                { locationId: fromLocationId, bucket: 'damaged', delta: quantity },
            ];
        case InventoryTransactionType.LOST:
            requireFrom();
            forbidTo();
            return [
                { locationId: fromLocationId, bucket: 'onHand', delta: -quantity },
                { locationId: fromLocationId, bucket: 'lost', delta: quantity },
            ];
        // Reservation only earmarks stock (reduces `available` via the reserved
        // bucket) — on_hand is untouched until actual dispatch (Phase 1E/1F).
        case InventoryTransactionType.RESERVATION:
            requireFrom();
            forbidTo();
            return [{ locationId: fromLocationId, bucket: 'reserved', delta: quantity }];
        case InventoryTransactionType.RELEASE_RESERVATION:
            requireFrom();
            forbidTo();
            return [{ locationId: fromLocationId, bucket: 'reserved', delta: -quantity }];
        // Generic manual corrections. Caller picks the bucket (default onHand)
        // and the direction: toLocationId increases it, fromLocationId
        // decreases it — exactly one of the two, never both (that's TRANSFER).
        case InventoryTransactionType.ADJUSTMENT:
        case InventoryTransactionType.STOCK_COUNT: {
            const targetBucket = bucket ?? 'onHand';
            if (fromLocationId && toLocationId) {
                throw badRequest(`${type} accepts only one of fromLocationId/toLocationId`);
            }
            if (toLocationId)
                return [{ locationId: toLocationId, bucket: targetBucket, delta: quantity }];
            if (fromLocationId)
                return [{ locationId: fromLocationId, bucket: targetBucket, delta: -quantity }];
            throw badRequest(`${type} requires fromLocationId or toLocationId`);
        }
        default: {
            const exhaustive = type;
            throw badRequest(`Unsupported transaction type: ${exhaustive}`);
        }
    }
}
