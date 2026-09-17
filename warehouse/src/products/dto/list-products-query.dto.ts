import { ApiPropertyOptional } from '@nestjs/swagger';
import { ProductStatus } from '@prisma/client';
import { Transform } from 'class-transformer';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUUID } from 'class-validator';

export class ListProductsQueryDto {
  @ApiPropertyOptional({ description: 'Filter by category id' })
  @IsOptional()
  @IsUUID('4')
  categoryId?: string;

  @ApiPropertyOptional({
    description: "Filter by workstream (via the product's category), a product has no workstream of its own",
  })
  @IsOptional()
  @IsUUID('4')
  workstreamId?: string;

  @ApiPropertyOptional({
    enum: ProductStatus,
    description: 'Filter to an exact status. Overrides includeInactive.',
  })
  @IsOptional()
  @IsEnum(ProductStatus)
  status?: ProductStatus;

  @ApiPropertyOptional({
    default: false,
    description: 'Include soft-deleted (INACTIVE) products when no explicit status filter is set',
  })
  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  includeInactive?: boolean;

  @ApiPropertyOptional({ description: 'Case-insensitive match against SKU or name' })
  @IsOptional()
  @IsString()
  search?: string;
}
