import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsUUID, ValidateNested } from 'class-validator';

export class ReserveOrderAllocationDto {
  @ApiProperty({ description: 'An order_items.id belonging to this order' })
  @IsUUID('4')
  orderItemId: string;

  @ApiProperty({ description: 'Leaf location to reserve this item\'s stock from' })
  @IsUUID('4')
  locationId: string;
}

// Multi-warehouse pulling (Open Decision #6) isn't resolved — rather than
// silently assume single-warehouse, the caller states explicitly where
// each item is reserved from. Must cover exactly the order's items, no
// missing/extra (same validation shape as stock count submission).
export class ReserveOrderDto {
  @ApiProperty({ type: [ReserveOrderAllocationDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => ReserveOrderAllocationDto)
  allocations: ReserveOrderAllocationDto[];
}
