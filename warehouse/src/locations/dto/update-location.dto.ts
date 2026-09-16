import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MinLength } from 'class-validator';

// Intentionally excludes parentId — repositioning a location in the tree is
// a distinct action (POST /locations/:id/move), not a generic field edit.
export class UpdateLocationDto {
  @ApiPropertyOptional({ example: 'Rack A1' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional({ example: 'A1' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  code?: string;

  @ApiPropertyOptional({ example: 'RACK' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  locationType?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({ description: 'Reactivate (true) or soft-delete (false) this location' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
