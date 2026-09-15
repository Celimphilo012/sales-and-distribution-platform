import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class RejectAdjustmentDto {
  @ApiProperty({ example: 'Count discrepancy within tolerance — no correction needed', description: 'Mandatory — why this request was rejected' })
  @IsString()
  @MinLength(1)
  reviewNote: string;
}
