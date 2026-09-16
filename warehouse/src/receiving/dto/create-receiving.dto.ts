import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsDateString, IsNumber, IsOptional, IsPositive, IsString, IsUUID, MinLength } from 'class-validator';

export class CreateReceivingDto {
  @ApiProperty({ example: 'Acme Distributors', description: 'Supplier name (free text — no supplier module yet)' })
  @IsString()
  @MinLength(1)
  supplier: string;

  @ApiProperty()
  @IsUUID('4')
  productId: string;

  @ApiProperty({ example: 100, description: 'Quantity received, up to 3 decimal places' })
  @IsNumber({ maxDecimalPlaces: 3 })
  @IsPositive()
  quantity: number;

  @ApiProperty({ description: 'Destination location — must be a leaf location' })
  @IsUUID('4')
  toLocationId: string;

  @ApiPropertyOptional({ description: 'When the goods were physically received, if different from now' })
  @IsOptional()
  @IsDateString()
  receivedDate?: string;

  @ApiPropertyOptional({ example: 'GRN-2026-00042', description: 'Delivery/reference document number' })
  @IsOptional()
  @IsString()
  reference?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;
}
