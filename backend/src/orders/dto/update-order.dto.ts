import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsOptional, IsString, ValidateNested } from 'class-validator';
import { OrderItemInputDto } from './order-item-input.dto';

// PATCH /orders/:id: DRAFT-only, owner-only field edits (see
// OrdersController). Items, when provided, REPLACE the full set — same
// "replace, don't patch individual rows" convention as RolesController's
// assign-permissions.
export class UpdateOrderDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  deliveryInfo?: string;

  @ApiPropertyOptional({ type: [OrderItemInputDto] })
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => OrderItemInputDto)
  items?: OrderItemInputDto[];
}
