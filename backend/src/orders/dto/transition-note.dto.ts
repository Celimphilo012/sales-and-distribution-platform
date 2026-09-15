import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString } from 'class-validator';

// Used for submit/approve/cancel — an optional note on the resulting
// order_status_history row.
export class TransitionNoteDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  note?: string;
}
