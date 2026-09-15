import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsOptional, IsUUID } from 'class-validator';

// Shared by /reports/adjustments, /reports/receiving, /reports/transfers —
// each fixes `type` itself, so only product/location/date filters vary.
export class LedgerReportQueryDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID('4')
  productId?: string;

  @ApiPropertyOptional({ description: 'Matches either side of a transfer (fromLocationId or toLocationId)' })
  @IsOptional()
  @IsUUID('4')
  locationId?: string;

  @ApiPropertyOptional({ description: 'ISO date/time, inclusive lower bound on created_at' })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({ description: 'ISO date/time, inclusive upper bound on created_at' })
  @IsOptional()
  @IsDateString()
  to?: string;
}
