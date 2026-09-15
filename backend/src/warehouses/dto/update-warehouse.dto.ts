import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateWarehouseDto {
  @ApiPropertyOptional({ example: 'Main Distribution Centre' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional({ example: 'WH-MAIN' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  code?: string;

  @ApiPropertyOptional({ description: 'Reactivate (true) or soft-delete (false) this warehouse' })
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
