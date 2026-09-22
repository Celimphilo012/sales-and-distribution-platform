import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';

/** Shared by the two period-scoped reports (stock-movement-summary, adjustments-summary). */
export class PeriodQueryDto {
  @ApiPropertyOptional({ default: 7, minimum: 1, maximum: 365, description: 'Lookback window in days' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(365)
  days?: number;
}
