import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional } from 'class-validator';

export class ListAttributeTypesQueryDto {
  @ApiPropertyOptional({ default: false, description: 'Include deactivated (is_active=false) attribute types' })
  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  includeInactive?: boolean;
}
