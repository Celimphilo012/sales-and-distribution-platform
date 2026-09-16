import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMinSize, ArrayUnique, IsArray, IsOptional, IsUUID } from 'class-validator';

export class CreateStockCountDto {
  @ApiProperty({ description: 'Location to count — must be a leaf location' })
  @IsUUID('4')
  locationId: string;

  @ApiPropertyOptional({
    description:
      'Restrict the count to these products. Omit to snapshot every product that currently has an inventory_balances row at this location.',
    type: [String],
  })
  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  productIds?: string[];
}
