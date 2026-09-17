import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class CreateWorkstreamDto {
  @ApiProperty({ description: 'Warehouse this workstream belongs to' })
  @IsUUID('4')
  warehouseId: string;

  @ApiProperty({ example: 'Retail' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ example: 'RETAIL' })
  @IsString()
  @MinLength(1)
  code: string;

  @ApiPropertyOptional({ example: 'Retail-facing catalogue' })
  @IsOptional()
  @IsString()
  description?: string;
}
