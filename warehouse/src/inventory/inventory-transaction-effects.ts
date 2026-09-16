import { InventoryTransactionType } from '@prisma/client';
import { BadRequestException } from '@nestjs/common';

/**
 * The five distinct buckets (rule 4). `available` is never stored — it is
 * always computed as on_hand - reserved.
 */
export type InventoryBucket = 'onHand' | 'reserved' | 'damaged' | 'lost' | 'expired';

export interface BucketDelta {
  locationId: string;
  bucket: InventoryBucket;
  delta: number;
}

export interface TransactionEffectInput {
  type: InventoryTransactionType;
  quantity: number;
  fromLocationId?: string;
  toLocationId?: string;
  /** Only meaningful for ADJUSTMENT / STOCK_COUNT — which bucket is being corrected. Defaults to onHand. */
  bucket?: InventoryBucket;
}

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
export function resolveBucketDeltas(input: TransactionEffectInput): BucketDelta[] {
  const { type, quantity, fromLocationId, toLocationId, bucket } = input;

  const requireFrom = () => {
    if (!fromLocationId) throw new BadRequestException(`${type} requires fromLocationId`);
  };
  const requireTo = () => {
    if (!toLocationId) throw new BadRequestException(`${type} requires toLocationId`);
  };
  const forbidFrom = () => {
    if (fromLocationId) throw new BadRequestException(`${type} does not accept fromLocationId`);
  };
  const forbidTo = () => {
    if (toLocationId) throw new BadRequestException(`${type} does not accept toLocationId`);
  };

  switch (type) {
    // Stock enters the system at a location.
    case InventoryTransactionType.RECEIVE:
    case InventoryTransactionType.RETURN:
      requireTo();
      forbidFrom();
      return [{ locationId: toLocationId!, bucket: 'onHand', delta: quantity }];

    // Stock leaves the system from a location.
    case InventoryTransactionType.ISSUE:
    case InventoryTransactionType.SALE:
      requireFrom();
      forbidTo();
      return [{ locationId: fromLocationId!, bucket: 'onHand', delta: -quantity }];

    // Stock physically moves between two locations (§H point 3).
    case InventoryTransactionType.TRANSFER:
      requireFrom();
      requireTo();
      if (fromLocationId === toLocationId) {
        throw new BadRequestException('TRANSFER requires two different locations');
      }
      return [
        { locationId: fromLocationId!, bucket: 'onHand', delta: -quantity },
        { locationId: toLocationId!, bucket: 'onHand', delta: quantity },
      ];

    // Same-location bucket reclassification: sellable stock leaves on_hand
    // and enters the damaged/lost bucket. Never a silent overwrite (rule 4)
    // — both sides of the move are recorded as explicit deltas.
    case InventoryTransactionType.DAMAGED:
      requireFrom();
      forbidTo();
      return [
        { locationId: fromLocationId!, bucket: 'onHand', delta: -quantity },
        { locationId: fromLocationId!, bucket: 'damaged', delta: quantity },
      ];

    case InventoryTransactionType.LOST:
      requireFrom();
      forbidTo();
      return [
        { locationId: fromLocationId!, bucket: 'onHand', delta: -quantity },
        { locationId: fromLocationId!, bucket: 'lost', delta: quantity },
      ];

    // Reservation only earmarks stock (reduces `available` via the reserved
    // bucket) — on_hand is untouched until actual dispatch (Phase 1E/1F).
    case InventoryTransactionType.RESERVATION:
      requireFrom();
      forbidTo();
      return [{ locationId: fromLocationId!, bucket: 'reserved', delta: quantity }];

    case InventoryTransactionType.RELEASE_RESERVATION:
      requireFrom();
      forbidTo();
      return [{ locationId: fromLocationId!, bucket: 'reserved', delta: -quantity }];

    // Generic manual corrections. Caller picks the bucket (default onHand)
    // and the direction: toLocationId increases it, fromLocationId
    // decreases it — exactly one of the two, never both (that's TRANSFER).
    case InventoryTransactionType.ADJUSTMENT:
    case InventoryTransactionType.STOCK_COUNT: {
      const targetBucket = bucket ?? 'onHand';
      if (fromLocationId && toLocationId) {
        throw new BadRequestException(`${type} accepts only one of fromLocationId/toLocationId`);
      }
      if (toLocationId) return [{ locationId: toLocationId, bucket: targetBucket, delta: quantity }];
      if (fromLocationId) return [{ locationId: fromLocationId, bucket: targetBucket, delta: -quantity }];
      throw new BadRequestException(`${type} requires fromLocationId or toLocationId`);
    }

    default: {
      const exhaustive: never = type;
      throw new BadRequestException(`Unsupported transaction type: ${exhaustive}`);
    }
  }
}
