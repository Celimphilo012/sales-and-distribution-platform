import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class RejectOrderDto {
  @ApiProperty({ example: 'Customer credit hold', description: 'Mandatory — why this order was rejected' })
  @IsString()
  @MinLength(1)
  note: string;
}
