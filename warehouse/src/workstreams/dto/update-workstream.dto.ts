import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateWorkstreamDto {
  @ApiPropertyOptional({ example: 'Retail' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional({ example: 'RETAIL' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  code?: string;

  @ApiPropertyOptional({ example: 'Retail-facing catalogue' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({ description: 'Reactivate (true) or deactivate (false) this workstream' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
