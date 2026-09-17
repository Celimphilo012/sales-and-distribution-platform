import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
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

export class CreateProductDto {
  @ApiProperty({ example: 'BEV-COLA-330' })
  @IsString()
  @MinLength(1)
  sku: string;

  @ApiProperty({ example: 'Cola 330ml Can' })
  @IsString()
  @MinLength(1)
  name: string;

  @ApiPropertyOptional({ example: 'Carbonated cola soft drink, 330ml can' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiProperty({ description: 'Category this product belongs to' })
  @IsUUID('4')
  categoryId: string;

  @ApiProperty({ example: 12.5, description: 'Selling price, up to 2 decimal places' })
  @IsNumber({ maxDecimalPlaces: 2 })
  @IsPositive()
  sellingPrice: number;

  @ApiPropertyOptional({ example: 8.0, description: 'Cost price, up to 2 decimal places' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  costPrice?: number;

  @ApiProperty({ example: 'EACH', description: 'Unit of measure, e.g. EACH, KG, BOX' })
  @IsString()
  @MinLength(1)
  uom: string;

  @ApiPropertyOptional({ example: 0, description: 'Reorder threshold used by inventory alerts' })
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  minStockLevel?: number;

  @ApiPropertyOptional({
    type: [ProductAttributeInputDto],
    description:
      'Descriptive metadata (colour, size, weight, ...) — NOT variants, stock stays per-product. One value per attribute type.',
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ProductAttributeInputDto)
  attributes?: ProductAttributeInputDto[];
}
