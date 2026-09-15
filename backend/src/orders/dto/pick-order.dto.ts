import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsNumber, IsUUID, Min, ValidateNested } from 'class-validator';

export class PickOrderItemDto {
  @ApiProperty({ description: 'An order_items.id belonging to this order' })
  @IsUUID('4')
  orderItemId: string;

  @ApiProperty({ example: 8, description: 'Quantity physically picked — may be less than ordered (short pick), never more' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  pickedQty: number;
}

// Must cover exactly the order's items (same shape as ReserveOrderDto's
// allocations). The location each item is picked from is NOT client
// input — it's recovered from the order's RESERVATION ledger rows, since
// that's already the validated leaf location the stock was earmarked at.
export class PickOrderDto {
  @ApiProperty({ type: [PickOrderItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PickOrderItemDto)
  items: PickOrderItemDto[];
}
