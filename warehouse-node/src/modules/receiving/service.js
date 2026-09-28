'use strict';

function createReceivingService({ inventory, locations }) {
  async function receive(dto, performedBy) {
    // Stock can only be held at leaf locations, in a warehouse the receiver may access.
    await locations.assertLeaf(dto.toLocationId, performedBy);

    // inventory_transactions has no supplier/notes/receivedDate columns — they are captured in
    // `reason` (reference stays a pure doc/PO number, matching its use everywhere else in the ledger).
    const reasonParts = [
      `Supplier: ${dto.supplier}`,
      dto.receivedDate ? `received ${dto.receivedDate}` : null,
      dto.notes,
    ].filter(Boolean);

    // The one and only write path for a stock change (rule 2).
    return inventory.applyTransaction({
      type: 'RECEIVE',
      productId: dto.productId,
      toLocationId: dto.toLocationId,
      quantity: dto.quantity,
      reason: reasonParts.join(' | '),
      reference: dto.reference ?? undefined,
      performedBy,
    });
  }

  return { receive };
}

module.exports = { createReceivingService };
