import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ArrayMinSize, IsArray, IsOptional, IsUUID, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class StockAvailabilityItemDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiPropertyOptional({ description: 'Omit to sum availability across every location for this product' })
  @IsOptional()
  @IsUUID('4')
  locationId?: string;
}

export class StockAvailabilityDto {
  @ApiProperty({ type: [StockAvailabilityItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => StockAvailabilityItemDto)
  items: StockAvailabilityItemDto[];
}
