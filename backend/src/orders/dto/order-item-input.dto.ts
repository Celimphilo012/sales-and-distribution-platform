import { ApiProperty } from '@nestjs/swagger';
import { IsNumber, IsPositive, IsUUID } from 'class-validator';

// Shared by create and edit-draft. unitPrice is never client-supplied (rule
// 8) — OrdersService.buildLineInputs() fetches the product from the
// warehouse catalogue (WarehouseApiClient.getProduct) and snapshots its
// current sellingPrice + name onto the order line server-side. This
// restores rule 8 across the system-split boundary: step 4 had briefly made
// unitPrice client-supplied because the catalogue had left this app; step 5
// closes that hole.
export class OrderItemInputDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ example: 5, description: 'Quantity ordered, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;
}
