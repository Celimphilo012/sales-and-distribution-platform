import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class CreateWarehouseDto {
  @ApiProperty({ example: 'Main Distribution Centre' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ example: 'WH-MAIN' })
  @IsString()
  @MinLength(1)
  code: string;
}
