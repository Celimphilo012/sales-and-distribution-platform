import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString } from 'class-validator';

export class ListCatalogueQueryDto {
  @ApiPropertyOptional({ description: 'Case-insensitive match against product name or SKU (relayed to the warehouse)' })
  @IsOptional()
  @IsString()
  search?: string;
}
