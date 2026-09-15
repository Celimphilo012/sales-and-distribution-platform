import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString } from 'class-validator';

export class ApproveAdjustmentDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  reviewNote?: string;
}
