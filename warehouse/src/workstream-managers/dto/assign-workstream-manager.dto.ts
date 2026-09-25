import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

export class AssignWorkstreamManagerDto {
  @ApiProperty({ description: 'The user to assign as a manager of this workstream' })
  @IsUUID('4')
  userId: string;
}
