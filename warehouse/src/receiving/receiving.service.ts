import { Injectable } from '@nestjs/common';
import { InventoryService } from '../inventory/inventory.service';
import { LocationsService } from '../locations/locations.service';
import { CreateReceivingDto } from './dto/create-receiving.dto';

@Injectable()
export class ReceivingService {
  constructor(
    private readonly inventoryService: InventoryService,
    private readonly locationsService: LocationsService,
  ) {}

  async receive(dto: CreateReceivingDto, performedBy: string) {
    // Stock can only be held at leaf locations (Phase 1D part 2 policy).
    await this.locationsService.assertLeaf(dto.toLocationId);

    // inventory_transactions has no supplier/notes/receivedDate columns —
    // they're captured in `reason` (reference stays a pure doc/PO number,
    // matching its use everywhere else in the ledger).
    const reasonParts = [
      `Supplier: ${dto.supplier}`,
      dto.receivedDate ? `received ${dto.receivedDate}` : null,
      dto.notes,
    ].filter((part): part is string => Boolean(part));

    // The one and only write path for a stock change (rule 2) — this is
    // Phase 1D part 1's frozen engine, reused as-is.
    return this.inventoryService.applyTransaction({
      type: 'RECEIVE',
      productId: dto.productId,
      toLocationId: dto.toLocationId,
      quantity: dto.quantity,
      reason: reasonParts.join(' | '),
      reference: dto.reference,
      performedBy,
    });
  }
}
