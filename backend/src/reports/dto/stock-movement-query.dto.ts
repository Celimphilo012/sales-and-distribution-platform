import { ApiPropertyOptional } from '@nestjs/swagger';
import { InventoryTransactionType } from '@prisma/client';
import { IsDateString, IsEnum, IsOptional, IsUUID } from 'class-validator';

export class StockMovementQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  productId?: string;

  @ApiPropertyOptional({ description: 'Matches either side of a transfer (fromLocationId or toLocationId)' })
  @IsOptional()
  @IsUUID('4')
  locationId?: string;

  @ApiPropertyOptional({ enum: InventoryTransactionType })
  @IsOptional()
  @IsEnum(InventoryTransactionType)
  type?: InventoryTransactionType;

  @ApiPropertyOptional({ description: 'ISO date/time, inclusive lower bound on created_at' })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({ description: 'ISO date/time, inclusive upper bound on created_at' })
  @IsOptional()
  @IsDateString()
  to?: string;
}
