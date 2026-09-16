import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class ReleaseStockDto {
  @ApiProperty({ example: 'ORDER-10042', description: 'The reference used when reserving' })
  @IsString()
  @MinLength(1)
  reference: string;
}
