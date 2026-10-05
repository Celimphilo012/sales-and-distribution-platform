'use strict';

const { badRequest } = require('../../core/errors');

function createReceivingService({ inventory, locations, products }) {
  async function receive(dto, performedBy) {
    // Stock can only be held at leaf locations, in a warehouse the receiver may access.
    await locations.assertLeaf(dto.toLocationId, performedBy);

    const product = await products.getExisting(dto.productId);
    const hasQuantity = dto.quantity !== undefined;
    const hasUnitCodes = dto.unitCodes !== undefined;
    if (product.trackingMode === 'SERIAL') {
      if (!hasUnitCodes) throw badRequest('This product is unit-tracked — scan each unit instead of entering a quantity');
      if (hasQuantity) throw badRequest('Unit-tracked products derive their quantity from the scanned units, not a typed number');
    } else if (hasUnitCodes) {
      throw badRequest('This product is not unit-tracked — enter a quantity instead of scanning unit codes');
    } else if (!hasQuantity) {
      throw badRequest('quantity is required');
    }

    // inventory_transactions has no supplier/notes/receivedDate columns — they are captured in
    // `reason` (reference stays a pure doc/PO number, matching its use everywhere else in the ledger).
    const reasonParts = [
      `Supplier: ${dto.supplier}`,
      dto.receivedDate ? `received ${dto.receivedDate}` : null,
      dto.notes,
    ].filter(Boolean);
    const reason = reasonParts.join(' | ');

    // Every scanned code is resolved (pre-printed label coming in, brand-new supplier barcode, or
    // rejected as already-received/foreign) BEFORE the ledger write — a rejection must not move stock.
    const unitIds = hasUnitCodes ? await inventory.resolveUnitsForReceive(dto.productId, dto.unitCodes) : undefined;

    // The one and only write path for a stock change (rule 2). unitIds, when present, is what makes
    // this unit-tracked — applyTransaction derives quantity from its length, never from dto.quantity.
    return inventory.applyTransaction({
      type: 'RECEIVE',
      productId: dto.productId,
      toLocationId: dto.toLocationId,
      quantity: dto.quantity,
      unitIds,
      reason,
      reference: dto.reference ?? undefined,
      performedBy,
    });
  }

  return { receive };
}

module.exports = { createReceivingService };
