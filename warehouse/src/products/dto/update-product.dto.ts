import { ApiPropertyOptional } from '@nestjs/swagger';
import { ProductStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { ProductAttributeInputDto } from './product-attribute-input.dto';

export class UpdateProductDto {
  @ApiPropertyOptional({ example: 'Cola 330ml Can' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({ description: 'Category this product belongs to' })
  @IsOptional()
  @IsUUID('4')
  categoryId?: string;

  @ApiPropertyOptional({ example: 12.5, description: 'Selling price, up to 2 decimal places' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  sellingPrice?: number;

  @ApiPropertyOptional({ example: 8.0, description: 'Cost price, up to 2 decimal places' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  costPrice?: number;

  @ApiPropertyOptional({ example: 'EACH' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  uom?: string;

  @ApiPropertyOptional({ example: 0 })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  minStockLevel?: number;

  @ApiPropertyOptional({ enum: ProductStatus })
  @IsOptional()
  @IsEnum(ProductStatus)
  status?: ProductStatus;

  @ApiPropertyOptional({
    type: [ProductAttributeInputDto],
    description:
      'When provided, REPLACES the product\'s full attribute set (omit this field entirely to leave attributes untouched; pass [] to clear them all).',
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ProductAttributeInputDto)
  attributes?: ProductAttributeInputDto[];
}
