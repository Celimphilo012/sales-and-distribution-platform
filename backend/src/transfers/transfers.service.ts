import { Injectable } from '@nestjs/common';
import { InventoryService } from '../inventory/inventory.service';
import { LocationsService } from '../locations/locations.service';
import { CreateTransferDto } from './dto/create-transfer.dto';

@Injectable()
export class TransfersService {
  constructor(
    private readonly inventoryService: InventoryService,
    private readonly locationsService: LocationsService,
  ) {}

  async transfer(dto: CreateTransferDto, performedBy: string) {
    // Both ends of a physical stock move must be leaf locations.
    await this.locationsService.assertLeaf(dto.fromLocationId);
    await this.locationsService.assertLeaf(dto.toLocationId);

    // One TRANSFER transaction moves both legs atomically — that's
    // InventoryService's job (§H point 3), reused as-is.
    return this.inventoryService.applyTransaction({
      type: 'TRANSFER',
      productId: dto.productId,
      fromLocationId: dto.fromLocationId,
      toLocationId: dto.toLocationId,
      quantity: dto.quantity,
      reason: dto.reason,
      reference: dto.reference,
      performedBy,
    });
  }
}
