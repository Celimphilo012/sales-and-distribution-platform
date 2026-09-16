import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class CreateLocationDto {
  @ApiPropertyOptional({
    description: 'Warehouse this location belongs to. Required when parentId is omitted (root location); ignored/validated against the parent when parentId is set.',
  })
  @IsOptional()
  @IsUUID('4')
  warehouseId?: string;

  @ApiPropertyOptional({ description: 'Parent location id. Omit to create a root location for the warehouse.' })
  @IsOptional()
  @IsUUID('4')
  parentId?: string;

  @ApiProperty({ example: 'Rack A1' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ example: 'A1', description: 'Unique within the warehouse' })
  @IsString()
  @MinLength(1)
  code: string;

  @ApiProperty({
    example: 'RACK',
    description: 'Free-form label (e.g. ZONE/AISLE/RACK/SHELF/LEVEL/BIN/PALLET/CAGE/ROOM/FLOOR/OTHER). Not a structural constraint — any string is accepted.',
  })
  @IsString()
  @MinLength(1)
  locationType: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;
}
