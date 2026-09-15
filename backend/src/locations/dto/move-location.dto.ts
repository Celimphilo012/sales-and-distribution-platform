import { ApiProperty } from '@nestjs/swagger';
import { IsUUID, ValidateIf } from 'class-validator';

export class MoveLocationDto {
  // Deliberately no @IsOptional(): the key must be present. null is a
  // meaningful, valid value (move to root) — a missing key is a client
  // error, not "no change".
  @ApiProperty({
    description: 'New parent location id, or null to move this location to the root of its warehouse.',
    nullable: true,
  })
  @ValidateIf((_, value) => value !== null)
  @IsUUID('4')
  parentId: string | null;
}
