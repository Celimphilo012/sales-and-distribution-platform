import { ApiPropertyOptional } from '@nestjs/swagger';
import { AdjustmentStatus } from '@prisma/client';
import { IsEnum, IsOptional } from 'class-validator';

export class ListAdjustmentsQueryDto {
  @ApiPropertyOptional({ enum: AdjustmentStatus })
  @IsOptional()
  @IsEnum(AdjustmentStatus)
  status?: AdjustmentStatus;
}
