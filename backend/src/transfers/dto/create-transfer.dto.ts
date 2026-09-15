import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNumber, IsOptional, IsPositive, IsString, IsUUID } from 'class-validator';

export class CreateTransferDto {
  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ example: 20, description: 'Quantity to move, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;

  @ApiProperty({ description: 'Source location — must be a leaf location' })
  @IsUUID('4')
  fromLocationId: string;

  @ApiProperty({ description: 'Destination location — must be a leaf location' })
  @IsUUID('4')
  toLocationId: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  reason?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  reference?: string;
}
