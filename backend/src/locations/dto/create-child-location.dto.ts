import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, MinLength } from 'class-validator';

// Same shape as CreateLocationDto minus warehouseId/parentId, which are
// derived from the route (:id is the parent; warehouseId is inherited).
export class CreateChildLocationDto {
  @ApiProperty({ example: 'Shelf 1' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiProperty({ example: 'A1-S1', description: 'Unique within the warehouse' })
  @IsString()
  @MinLength(1)
  code: string;

  @ApiProperty({ example: 'SHELF' })
  @IsString()
  @MinLength(1)
  locationType: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;
}
