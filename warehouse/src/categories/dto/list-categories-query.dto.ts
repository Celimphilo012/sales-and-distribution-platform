import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional, IsUUID } from 'class-validator';

export class ListCategoriesQueryDto {
  @ApiPropertyOptional({ default: false, description: 'Include soft-deleted (is_active=false) categories' })
  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  includeInactive?: boolean;

  @ApiPropertyOptional({ description: 'Filter to direct children of this category id' })
  @IsOptional()
  @IsUUID('4')
  parentId?: string;
}
