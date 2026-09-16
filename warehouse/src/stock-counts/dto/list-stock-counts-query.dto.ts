import { ApiPropertyOptional } from '@nestjs/swagger';
import { StockCountStatus } from '@prisma/client';
import { IsEnum, IsOptional, IsUUID } from 'class-validator';

export class ListStockCountsQueryDto {
  @ApiPropertyOptional({ enum: StockCountStatus })
  @IsOptional()
  @IsEnum(StockCountStatus)
  status?: StockCountStatus;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  locationId?: string;
}
