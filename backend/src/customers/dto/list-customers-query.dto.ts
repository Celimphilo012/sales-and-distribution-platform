import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class ListCustomersQueryDto {
  @ApiPropertyOptional({ default: false, description: 'Include soft-deleted (status=INACTIVE) customers' })
  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  includeInactive?: boolean;

  @ApiPropertyOptional({ description: 'Case-insensitive match against name or phone' })
  @IsOptional()
  @IsString()
  search?: string;
}
