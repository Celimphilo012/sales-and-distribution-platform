import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsNumber, IsUUID, Min, ValidateNested } from 'class-validator';

export class PackOrderItemDto {
  @ApiProperty({ description: 'An order_items.id belonging to this order' })
  @IsUUID('4')
  orderItemId: string;

  @ApiProperty({ example: 8, description: 'Quantity confirmed packed — must not exceed the picked quantity' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @Min(0)
  packedQty: number;
}

export class PackOrderDto {
  @ApiProperty({ type: [PackOrderItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => PackOrderItemDto)
  items: PackOrderItemDto[];
}
