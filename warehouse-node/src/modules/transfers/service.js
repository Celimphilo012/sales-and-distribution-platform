'use strict';

function createTransfersService({ inventory, locations }) {
  async function transfer(dto, performedBy) {
    // Both ends of a physical stock move must be leaf locations.
    await locations.assertLeaf(dto.fromLocationId);
    await locations.assertLeaf(dto.toLocationId);

    // One TRANSFER transaction moves both legs atomically — that is InventoryService's job.
    return inventory.applyTransaction({
      type: 'TRANSFER',
      productId: dto.productId,
      fromLocationId: dto.fromLocationId,
      toLocationId: dto.toLocationId,
      quantity: dto.quantity,
      reason: dto.reason ?? undefined,
      reference: dto.reference ?? undefined,
      performedBy,
    });
  }

  return { transfer };
}

module.exports = { createTransfersService };
