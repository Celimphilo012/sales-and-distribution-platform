import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsUUID } from 'class-validator';

export class ListBalancesQueryDto {
  @ApiPropertyOptional({ description: 'Filter to a single product' })
  @IsOptional()
  @IsUUID('4')
  productId?: string;

  @ApiPropertyOptional({ description: 'Filter to a single location' })
  @IsOptional()
  @IsUUID('4')
  locationId?: string;

  @ApiPropertyOptional({ description: 'Filter to any location within this warehouse' })
  @IsOptional()
  @IsUUID('4')
  warehouseId?: string;
}
